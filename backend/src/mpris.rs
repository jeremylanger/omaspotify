use mpris_server::{
    LoopStatus, Metadata, PlaybackRate, PlaybackStatus as MprisPlaybackStatus, PlayerInterface,
    Property, RootInterface, Server, Signal, Time, TrackId, Volume,
    zbus::{Result as ZbusResult, fdo},
};
use tokio::sync::watch;

use crate::{
    engine::{EngineSender, send_without_reply},
    protocol::{Command, PlaybackStatus, RepeatMode},
    state::StateStore,
};

pub struct MprisAdapter {
    state: StateStore,
    commands: EngineSender,
    shutdown: watch::Sender<bool>,
}

impl MprisAdapter {
    fn send(&self, command: Command) -> fdo::Result<()> {
        send_without_reply(&self.commands, command)
            .map_err(|error| fdo::Error::Failed(error.message))
    }
}

impl RootInterface for MprisAdapter {
    async fn raise(&self) -> fdo::Result<()> {
        Ok(())
    }
    async fn quit(&self) -> fdo::Result<()> {
        let _ = self.shutdown.send(true);
        Ok(())
    }
    async fn can_quit(&self) -> fdo::Result<bool> {
        Ok(true)
    }
    async fn fullscreen(&self) -> fdo::Result<bool> {
        Ok(false)
    }
    async fn set_fullscreen(&self, _fullscreen: bool) -> ZbusResult<()> {
        Ok(())
    }
    async fn can_set_fullscreen(&self) -> fdo::Result<bool> {
        Ok(false)
    }
    async fn can_raise(&self) -> fdo::Result<bool> {
        Ok(false)
    }
    async fn has_track_list(&self) -> fdo::Result<bool> {
        Ok(false)
    }
    async fn identity(&self) -> fdo::Result<String> {
        Ok("OmaSpotify (librespot)".into())
    }
    async fn desktop_entry(&self) -> fdo::Result<String> {
        Ok("omaspotify".into())
    }
    async fn supported_uri_schemes(&self) -> fdo::Result<Vec<String>> {
        Ok(vec!["spotify".into()])
    }
    async fn supported_mime_types(&self) -> fdo::Result<Vec<String>> {
        Ok(Vec::new())
    }
}

impl PlayerInterface for MprisAdapter {
    async fn next(&self) -> fdo::Result<()> {
        self.send(Command::Next)
    }
    async fn previous(&self) -> fdo::Result<()> {
        self.send(Command::Previous)
    }
    async fn pause(&self) -> fdo::Result<()> {
        self.send(Command::Pause)
    }
    async fn play_pause(&self) -> fdo::Result<()> {
        self.send(Command::Toggle)
    }
    async fn stop(&self) -> fdo::Result<()> {
        self.send(Command::Stop)
    }
    async fn play(&self) -> fdo::Result<()> {
        self.send(Command::Play)
    }

    async fn seek(&self, offset: Time) -> fdo::Result<()> {
        let position = self.state.with(|state| {
            i64::from(state.position_ms)
                .saturating_add(offset.as_millis())
                .clamp(
                    0,
                    state
                        .track
                        .as_ref()
                        .map_or(i64::from(u32::MAX), |track| i64::from(track.duration_ms)),
                )
        });
        self.send(Command::Seek {
            position_ms: position as u32,
        })
    }

    async fn set_position(&self, track_id: TrackId, position: Time) -> fdo::Result<()> {
        let position_ms = position.as_millis();
        let valid = self.state.with(|state| {
            state.track.as_ref().is_some_and(|track| {
                track_id == track_id_for(&track.uri)
                    && position_ms >= 0
                    && position_ms <= i64::from(track.duration_ms)
            })
        });
        if !valid {
            return Ok(());
        }
        self.send(Command::Seek {
            position_ms: position_ms as u32,
        })
    }

    async fn open_uri(&self, uri: String) -> fdo::Result<()> {
        let is_context = [
            "spotify:album:",
            "spotify:artist:",
            "spotify:playlist:",
            "spotify:show:",
        ]
        .iter()
        .any(|prefix| uri.starts_with(prefix));
        self.send(Command::Load {
            context_uri: is_context.then_some(uri.clone()),
            uris: if is_context { Vec::new() } else { vec![uri] },
            offset_uri: None,
            offset_index: None,
            position_ms: 0,
            play: true,
        })
    }

    async fn playback_status(&self) -> fdo::Result<MprisPlaybackStatus> {
        Ok(self.state.with(|state| playback_status(state.playback)))
    }
    async fn loop_status(&self) -> fdo::Result<LoopStatus> {
        Ok(self.state.with(|state| loop_status(state.repeat)))
    }
    async fn set_loop_status(&self, loop_status: LoopStatus) -> ZbusResult<()> {
        let mode = match loop_status {
            LoopStatus::None => RepeatMode::Off,
            LoopStatus::Playlist => RepeatMode::Context,
            LoopStatus::Track => RepeatMode::Track,
        };
        self.send(Command::SetRepeat { mode }).map_err(Into::into)
    }
    async fn rate(&self) -> fdo::Result<PlaybackRate> {
        Ok(1.0)
    }
    async fn set_rate(&self, _rate: PlaybackRate) -> ZbusResult<()> {
        Ok(())
    }
    async fn shuffle(&self) -> fdo::Result<bool> {
        Ok(self.state.with(|state| state.shuffle))
    }
    async fn set_shuffle(&self, shuffle: bool) -> ZbusResult<()> {
        self.send(Command::SetShuffle { enabled: shuffle })
            .map_err(Into::into)
    }
    async fn metadata(&self) -> fdo::Result<Metadata> {
        Ok(self.state.with(metadata))
    }
    async fn volume(&self) -> fdo::Result<Volume> {
        Ok(self
            .state
            .with(|state| f64::from(state.volume) / f64::from(u16::MAX)))
    }
    async fn set_volume(&self, volume: Volume) -> ZbusResult<()> {
        let volume = (volume.clamp(0.0, 1.0) * f64::from(u16::MAX)).round() as u16;
        self.send(Command::SetVolume { volume }).map_err(Into::into)
    }
    async fn position(&self) -> fdo::Result<Time> {
        Ok(self
            .state
            .with(|state| Time::from_millis(i64::from(state.position_ms))))
    }
    async fn minimum_rate(&self) -> fdo::Result<PlaybackRate> {
        Ok(1.0)
    }
    async fn maximum_rate(&self) -> fdo::Result<PlaybackRate> {
        Ok(1.0)
    }
    async fn can_go_next(&self) -> fdo::Result<bool> {
        Ok(true)
    }
    async fn can_go_previous(&self) -> fdo::Result<bool> {
        Ok(true)
    }
    async fn can_play(&self) -> fdo::Result<bool> {
        Ok(true)
    }
    async fn can_pause(&self) -> fdo::Result<bool> {
        Ok(true)
    }
    async fn can_seek(&self) -> fdo::Result<bool> {
        Ok(self.state.with(|state| state.track.is_some()))
    }
    async fn can_control(&self) -> fdo::Result<bool> {
        Ok(true)
    }
}

pub async fn serve(
    state: StateStore,
    commands: EngineSender,
    shutdown: watch::Sender<bool>,
) -> ZbusResult<()> {
    let adapter = MprisAdapter {
        state: state.clone(),
        commands,
        shutdown,
    };
    // mpris-server requests names with replacement enabled and documents that
    // each instance suffix must be unique. A PID-qualified name prevents a
    // stray second backend from stealing MPRIS ownership from the supervised
    // service; clients discover players by identity/desktop entry.
    let server = Server::new(&bus_name_suffix(std::process::id()), adapter).await?;
    let mut states = state.subscribe();
    let (
        mut previous_playback,
        mut previous_track,
        mut previous_volume,
        mut previous_shuffle,
        mut previous_repeat,
        mut previous_seek_sequence,
    ) = {
        let initial = states.borrow();
        (
            initial.playback,
            initial.track.clone(),
            initial.volume,
            initial.shuffle,
            initial.repeat,
            initial.seek_sequence,
        )
    };

    while states.changed().await.is_ok() {
        let (changed, seeked) = {
            let current = states.borrow_and_update();
            let mut changed = Vec::new();
            if current.playback != previous_playback {
                changed.push(Property::PlaybackStatus(playback_status(current.playback)));
                previous_playback = current.playback;
            }
            if current.track != previous_track {
                changed.push(Property::Metadata(metadata(&current)));
                changed.push(Property::CanSeek(current.track.is_some()));
                previous_track = current.track.clone();
            }
            if current.volume != previous_volume {
                changed.push(Property::Volume(
                    f64::from(current.volume) / f64::from(u16::MAX),
                ));
                previous_volume = current.volume;
            }
            if current.shuffle != previous_shuffle {
                changed.push(Property::Shuffle(current.shuffle));
                previous_shuffle = current.shuffle;
            }
            if current.repeat != previous_repeat {
                changed.push(Property::LoopStatus(loop_status(current.repeat)));
                previous_repeat = current.repeat;
            }
            let seeked = (current.seek_sequence != previous_seek_sequence)
                .then(|| Time::from_millis(i64::from(current.position_ms)));
            previous_seek_sequence = current.seek_sequence;
            (changed, seeked)
        };
        if !changed.is_empty() {
            server.properties_changed(changed).await?;
        }
        if let Some(position) = seeked {
            server.emit(Signal::Seeked { position }).await?;
        }
    }
    Ok(())
}

fn playback_status(status: PlaybackStatus) -> MprisPlaybackStatus {
    match status {
        PlaybackStatus::Playing => MprisPlaybackStatus::Playing,
        PlaybackStatus::Paused => MprisPlaybackStatus::Paused,
        PlaybackStatus::Stopped | PlaybackStatus::Loading => MprisPlaybackStatus::Stopped,
    }
}

fn loop_status(mode: RepeatMode) -> LoopStatus {
    match mode {
        RepeatMode::Off => LoopStatus::None,
        RepeatMode::Context => LoopStatus::Playlist,
        RepeatMode::Track => LoopStatus::Track,
    }
}

fn metadata(state: &crate::protocol::BackendState) -> Metadata {
    let Some(track) = &state.track else {
        return Metadata::new();
    };
    let mut metadata = Metadata::new();
    metadata.set_trackid(Some(track_id_for(&track.uri)));
    metadata.set_length(Some(Time::from_millis(i64::from(track.duration_ms))));
    if !track.art_url.is_empty() {
        metadata.set_art_url(Some(track.art_url.clone()));
    }
    if !track.album.is_empty() {
        metadata.set_album(Some(track.album.clone()));
    }
    if !track.artists.is_empty() {
        metadata.set_artist(Some(track.artists.clone()));
    }
    metadata.set_title(Some(track.title.clone()));
    metadata.set_url(Some(track.uri.clone()));
    metadata
}

fn track_id_for(uri: &str) -> TrackId {
    let mut id = uri
        .rsplit(':')
        .next()
        .unwrap_or("track")
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || *character == '_')
        .collect::<String>();
    if id.is_empty() {
        id = "track".to_string();
    }
    TrackId::try_from(format!("/com/github/OmaSpotify/track/{id}")).unwrap_or(TrackId::NO_TRACK)
}

fn bus_name_suffix(process_id: u32) -> String {
    format!("OmaSpotify.instance{process_id}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{BackendState, Track};

    #[test]
    fn metadata_preserves_spotify_uri_for_qml() {
        let state = BackendState {
            track: Some(Track {
                uri: "spotify:track:abc123".into(),
                title: "A title".into(),
                artists: vec!["An artist".into()],
                album: "An album".into(),
                art_url: "https://i.scdn.co/image/example".into(),
                duration_ms: 42_000,
                item_type: "track".into(),
            }),
            ..BackendState::default()
        };
        let metadata = metadata(&state);
        assert_eq!(metadata.title(), Some("A title"));
        assert_eq!(metadata.url().as_deref(), Some("spotify:track:abc123"));
        assert_eq!(metadata.length(), Some(Time::from_millis(42_000)));
    }

    #[test]
    fn mpris_name_is_unique_and_has_a_valid_non_numeric_component() {
        assert_eq!(bus_name_suffix(42), "OmaSpotify.instance42");
    }
}
