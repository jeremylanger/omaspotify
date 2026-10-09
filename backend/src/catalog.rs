//! Playlist contents read through the signed-in librespot session.
//!
//! The Web API answers 403 for a personal app on playlists the account does
//! not own and spends a daily quota on the rest, while the Connect session
//! already holds every list the account can see. Rows are emitted in the Web
//! API's own playlist-item shape, so the plugin's cache and pages need no
//! second codec and fall back to the Web API without noticing a difference.

use std::{collections::HashMap, sync::Arc, time::Duration};

use base64::Engine as _;
use librespot_core::{Session, SpotifyUri};
use librespot_metadata::{
    Metadata, Playlist, Track,
    album::{Album, AlbumType},
    artist::Artists,
    image::Images,
    playlist::{attribute::PlaylistAttributes, item::PlaylistItem},
};
use librespot_protocol::{
    extended_metadata::{BatchedEntityRequest, EntityRequest, ExtensionQuery},
    extension_kind::ExtensionKind,
    metadata::Track as TrackMessage,
};
use protobuf::{EnumOrUnknown, Message};
use serde_json::{Value, json};
use tokio::sync::{Semaphore, watch};

use crate::protocol::ProtocolError;

/// Rows per answer when the caller names no limit; matches the Web API's
/// own page sizes closely enough that the plugin's paging needs no change.
pub const DEFAULT_LIMIT: u32 = 100;
/// The most rows one answer carries. The socket frames one line per message.
pub const MAX_LIMIT: u32 = 500;
/// Entities per extended-metadata request. Spotify's own clients batch in
/// this order of magnitude; one request fetches a whole page.
const METADATA_BATCH: usize = 100;
/// Longer than any healthy Spotify answer, shorter than the plugin's patience.
const FETCH_TIMEOUT: Duration = Duration::from_secs(45);
/// Lists fetched at once across every client. The warmer and an opened page
/// may overlap; a third caller waits its turn rather than racing Spotify.
const CONCURRENT_FETCHES: usize = 2;

/// Reads playlists with whatever session the engine currently holds.
#[derive(Clone)]
pub struct Catalog {
    session: watch::Receiver<Session>,
    permits: Arc<Semaphore>,
}

impl Catalog {
    pub fn new(session: watch::Receiver<Session>) -> Self {
        Self {
            session,
            permits: Arc::new(Semaphore::new(CONCURRENT_FETCHES)),
        }
    }

    /// One page of a playlist as `{ snapshot_id, name, owner, images, total,
    /// offset, limit, items, next }`, with `items` shaped like
    /// `GET /playlists/{id}/items` rows and `next` the following offset.
    pub async fn playlist_items(
        &self,
        uri: &str,
        offset: u32,
        limit: Option<u32>,
    ) -> Result<Value, ProtocolError> {
        let playlist_uri = SpotifyUri::from_uri(uri).map_err(|error| {
            ProtocolError::new(
                "invalid_request",
                format!("invalid Spotify URI {uri:?}: {error}"),
            )
        })?;
        if !matches!(playlist_uri, SpotifyUri::Playlist { .. }) {
            return Err(ProtocolError::new(
                "invalid_request",
                "playlist_items needs a spotify:playlist: URI",
            ));
        }
        let _permit = self.permits.acquire().await.map_err(|_| {
            ProtocolError::new("engine_unavailable", "playback engine is shutting down")
        })?;
        let session = self.session.borrow().clone();
        if session.is_invalid() {
            return Err(ProtocolError::new(
                "engine_reconnecting",
                "playback is reconnecting to Spotify",
            ));
        }
        let playlist = tokio::time::timeout(FETCH_TIMEOUT, Playlist::get(&session, &playlist_uri))
            .await
            .map_err(|_| {
                ProtocolError::new(
                    "playlist_timeout",
                    "Spotify took too long to list the playlist",
                )
            })?
            .map_err(|error| {
                ProtocolError::new(
                    "playlist_unavailable",
                    format!("Spotify did not list the playlist: {error}"),
                )
            })?;

        let items: &[PlaylistItem] = &playlist.contents.items;
        let (start, end) = page_bounds(items.len(), offset, limit);
        let page = &items[start..end];
        let tracks = fetch_tracks(&session, page.iter().map(|item| &item.id)).await?;
        let rows: Vec<Value> = page
            .iter()
            .map(|item| row_json(item, tracks.get(&item.id.to_uri())))
            .collect();
        let owner = match &playlist.id {
            SpotifyUri::Playlist { user, .. } => user.clone().unwrap_or_default(),
            _ => String::new(),
        };
        Ok(json!({
            "snapshot_id": snapshot_id(&playlist.revision),
            "name": playlist.name(),
            "owner": owner,
            "images": playlist_images(&playlist.attributes),
            "total": items.len(),
            "offset": start,
            "limit": end - start,
            "items": rows,
            "next": next_offset(start, end, items.len()),
        }))
    }
}

/// The slice of a list one answer covers. A limit of zero asks for the
/// list's version and length only, which is one request instead of two.
fn page_bounds(total: usize, offset: u32, limit: Option<u32>) -> (usize, usize) {
    let limit = limit.unwrap_or(DEFAULT_LIMIT).min(MAX_LIMIT) as usize;
    let start = (offset as usize).min(total);
    (start, (start + limit).min(total))
}

/// Where the following page starts, when this one carried rows and more
/// remain. A version check carries none and so continues nowhere.
fn next_offset(start: usize, end: usize, total: usize) -> Option<usize> {
    (end > start && end < total).then_some(end)
}

/// Track metadata for every track URI, keyed by URI. Episodes and local files
/// have no track metadata and end up absent, which the row shows as `null`,
/// the same way the Web API shows an unavailable row.
async fn fetch_tracks<'a>(
    session: &Session,
    uris: impl Iterator<Item = &'a SpotifyUri>,
) -> Result<HashMap<String, Track>, ProtocolError> {
    let mut wanted: Vec<String> = Vec::new();
    for uri in uris {
        if matches!(uri, SpotifyUri::Track { .. }) {
            let text = uri.to_uri();
            if !wanted.contains(&text) {
                wanted.push(text);
            }
        }
    }
    let mut tracks = HashMap::new();
    for batch in wanted.chunks(METADATA_BATCH) {
        let request = BatchedEntityRequest {
            entity_request: batch
                .iter()
                .map(|uri| EntityRequest {
                    entity_uri: uri.clone(),
                    query: vec![ExtensionQuery {
                        extension_kind: EnumOrUnknown::new(ExtensionKind::TRACK_V4),
                        ..Default::default()
                    }],
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        };
        let response = tokio::time::timeout(
            FETCH_TIMEOUT,
            session.spclient().get_extended_metadata(request),
        )
        .await
        .map_err(|_| {
            ProtocolError::new(
                "playlist_timeout",
                "Spotify took too long to describe the songs",
            )
        })?
        .map_err(|error| {
            ProtocolError::new(
                "playlist_unavailable",
                format!("Spotify did not describe the songs: {error}"),
            )
        })?;
        for array in response.extended_metadata {
            if array.extension_kind.enum_value_or_default() != ExtensionKind::TRACK_V4 {
                continue;
            }
            for data in array.extension_data {
                let Some(any) = data.extension_data.as_ref() else {
                    continue;
                };
                let Ok(message) = TrackMessage::parse_from_bytes(&any.value) else {
                    continue;
                };
                if let Ok(track) = Track::try_from(&message) {
                    tracks.insert(data.entity_uri.clone(), track);
                }
            }
        }
    }
    Ok(tracks)
}

/// Spotify's `snapshot_id` is the playlist revision in base64, so a version
/// read here compares equal to one the Web API listed.
fn snapshot_id(revision: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(revision)
}

fn row_json(item: &PlaylistItem, track: Option<&Track>) -> Value {
    let added = item.attributes.timestamp.as_timestamp_ms();
    json!({
        "added_at": if added > 0 { iso8601(&item.attributes.timestamp) } else { String::new() },
        "item": track.map(track_json),
    })
}

fn track_json(track: &Track) -> Value {
    let id = track.id.to_id();
    json!({
        "type": "track",
        "id": id,
        "uri": track.id.to_uri(),
        "name": track.name,
        "duration_ms": track.duration.max(0),
        "explicit": track.is_explicit,
        "track_number": track.number,
        "disc_number": track.disc_number,
        "is_local": false,
        "external_urls": { "spotify": format!("https://open.spotify.com/track/{id}") },
        "artists": artists_json(&track.artists),
        "album": album_json(&track.album),
    })
}

fn artists_json(artists: &Artists) -> Value {
    artists
        .iter()
        .map(|artist| {
            let id = artist.id.to_id();
            json!({
                "type": "artist",
                "id": id,
                "uri": artist.id.to_uri(),
                "name": artist.name,
                "external_urls": { "spotify": format!("https://open.spotify.com/artist/{id}") },
            })
        })
        .collect()
}

fn album_json(album: &Album) -> Value {
    let id = album.id.to_id();
    json!({
        "type": "album",
        "album_type": album_type(album.album_type),
        "id": id,
        "uri": album.id.to_uri(),
        "name": album.name,
        "release_date": release_date(album.date.year(), album.date.month() as u8, album.date.day()),
        "release_date_precision": "day",
        "images": images_json(&album.covers),
        "artists": artists_json(&album.artists),
        "external_urls": { "spotify": format!("https://open.spotify.com/album/{id}") },
    })
}

fn album_type(kind: AlbumType) -> &'static str {
    match kind {
        AlbumType::SINGLE | AlbumType::EP => "single",
        AlbumType::COMPILATION => "compilation",
        _ => "album",
    }
}

/// `YYYY-MM-DD` as the Web API writes it; a zero year is a missing date.
fn release_date(year: i32, month: u8, day: u8) -> String {
    if year <= 0 {
        return String::new();
    }
    format!("{year:04}-{month:02}-{day:02}")
}

fn iso8601(date: &librespot_core::date::Date) -> String {
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        date.year(),
        date.month() as u8,
        date.day(),
        date.hour(),
        date.minute(),
        date.second()
    )
}

/// Album covers largest first, as the Web API lists them, so the plugin's
/// size picker finds the same 640/300/64 ladder.
fn images_json(images: &Images) -> Value {
    let mut covers: Vec<(i32, i32, String)> = images
        .iter()
        .map(|image| {
            (
                image.width,
                image.height,
                format!("https://i.scdn.co/image/{}", image.id.to_base16()),
            )
        })
        .collect();
    covers.sort_by_key(|cover| std::cmp::Reverse(cover.0));
    covers
        .into_iter()
        .map(|(width, height, url)| json!({ "url": url, "width": width, "height": height }))
        .collect()
}

/// A playlist's own cover: Spotify sends ready-made URLs per size name, and
/// an image id for lists with a single uploaded picture.
fn playlist_images(attributes: &PlaylistAttributes) -> Value {
    let mut images: Vec<Value> = attributes
        .picture_sizes
        .iter()
        .map(|size| {
            let width = match size.target_name.as_str() {
                "small" => 64,
                "large" => 640,
                "xlarge" => 1000,
                _ => 300,
            };
            json!({ "url": size.url, "width": width, "height": width })
        })
        .collect();
    if images.is_empty() && !attributes.picture.is_empty() {
        let hex: String = attributes
            .picture
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        images.push(
            json!({ "url": format!("https://i.scdn.co/image/{hex}"), "width": 640, "height": 640 }),
        );
    }
    images.sort_by(|a, b| b["width"].as_i64().cmp(&a["width"].as_i64()));
    Value::Array(images)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_page_is_cut_at_the_list_and_the_cap() {
        assert_eq!(page_bounds(30, 0, None), (0, 30));
        assert_eq!(page_bounds(250, 100, None), (100, 200));
        assert_eq!(page_bounds(250, 240, Some(50)), (240, 250));
        assert_eq!(page_bounds(250, 900, Some(50)), (250, 250));
        assert_eq!(page_bounds(2000, 0, Some(9999)), (0, MAX_LIMIT as usize));
        assert_eq!(
            page_bounds(12, 3, Some(0)),
            (3, 3),
            "zero rows is a version check"
        );
    }

    #[test]
    fn only_a_page_with_rows_and_more_behind_it_continues() {
        assert_eq!(next_offset(0, 100, 250), Some(100));
        assert_eq!(
            next_offset(200, 250, 250),
            None,
            "the last page ends the list"
        );
        assert_eq!(
            next_offset(0, 0, 30),
            None,
            "a version check continues nowhere"
        );
        assert_eq!(next_offset(30, 30, 30), None);
    }

    #[test]
    fn snapshot_id_is_the_web_api_spelling_of_the_revision() {
        // Spotify's snapshot_id for revision 2 of a list starts "AAAAAn": four
        // big-endian bytes of the revision number, then the content hash.
        let mut revision = vec![0, 0, 0, 2];
        revision.extend_from_slice(&[
            0x75, 0xf2, 0x9c, 0x92, 0xf3, 0x03, 0xa9, 0xd8, 0x0c, 0xb5, 0xb3, 0x7d, 0xcc, 0x4d,
            0xd3, 0x15, 0x51, 0x1d, 0xd8, 0x88,
        ]);
        assert_eq!(snapshot_id(&revision), "AAAAAnXynJLzA6nYDLWzfcxN0xVRHdiI");
        assert_eq!(snapshot_id(&revision).len(), 32, "24 bytes need no padding");
    }

    #[test]
    fn album_kinds_fold_to_the_web_api_three() {
        assert_eq!(album_type(AlbumType::ALBUM), "album");
        assert_eq!(album_type(AlbumType::SINGLE), "single");
        assert_eq!(album_type(AlbumType::EP), "single");
        assert_eq!(album_type(AlbumType::COMPILATION), "compilation");
        assert_eq!(album_type(AlbumType::AUDIOBOOK), "album");
    }

    #[test]
    fn dates_are_written_the_web_api_way_or_not_at_all() {
        assert_eq!(release_date(2026, 4, 7), "2026-04-07");
        assert_eq!(release_date(0, 1, 1), "");
    }

    #[test]
    fn a_missing_track_is_a_null_row_that_keeps_its_place() {
        let date = librespot_core::date::Date::from_timestamp_ms(1_700_000_000_000).unwrap();
        let item = PlaylistItem {
            id: SpotifyUri::from_uri("spotify:track:4iV5W9uYEdYUVa79Axb7Rh").unwrap(),
            attributes: librespot_metadata::playlist::attribute::PlaylistItemAttributes {
                added_by: "someone".into(),
                timestamp: date,
                seen_at: librespot_core::date::Date::from_timestamp_ms(0).unwrap(),
                is_public: true,
                format_attributes: Default::default(),
                item_id: Vec::new(),
            },
        };
        let row = row_json(&item, None);
        assert!(row["item"].is_null());
        assert_eq!(row["added_at"], "2023-11-14T22:13:20Z");
    }
}
