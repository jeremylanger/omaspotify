use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u16 = 1;

#[derive(Clone, Debug, Deserialize, PartialEq)]
pub struct Request {
    pub v: u16,
    pub id: u64,
    #[serde(flatten)]
    pub command: Command,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum Command {
    Hello,
    Ping,
    GetState,
    Activate,
    Play,
    Pause,
    Toggle,
    Stop,
    Next,
    Previous,
    Seek {
        position_ms: u32,
    },
    SetVolume {
        volume: u16,
    },
    SetShuffle {
        enabled: bool,
    },
    SetRepeat {
        mode: RepeatMode,
    },
    Load {
        #[serde(default)]
        context_uri: Option<String>,
        #[serde(default)]
        uris: Vec<String>,
        #[serde(default)]
        offset_uri: Option<String>,
        #[serde(default)]
        offset_index: Option<u32>,
        #[serde(default)]
        position_ms: u32,
        #[serde(default = "default_true")]
        play: bool,
    },
    AddToQueue {
        uri: String,
    },
    /// One page of a playlist's rows, read through the Connect session
    /// instead of the Web API. A limit of 0 returns the version and length.
    PlaylistItems {
        uri: String,
        #[serde(default)]
        offset: u32,
        #[serde(default)]
        limit: Option<u32>,
    },
}

const fn default_true() -> bool {
    true
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RepeatMode {
    #[default]
    Off,
    Context,
    Track,
}

#[derive(Clone, Copy, Debug, Default, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Lifecycle {
    #[default]
    Starting,
    Ready,
    Error,
    Stopped,
}

#[derive(Clone, Copy, Debug, Default, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackStatus {
    #[default]
    Stopped,
    Loading,
    Playing,
    Paused,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct Track {
    pub uri: String,
    pub title: String,
    pub artists: Vec<String>,
    pub album: String,
    pub art_url: String,
    pub duration_ms: u32,
    pub item_type: String,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct BackendState {
    pub protocol_version: u16,
    pub backend_version: String,
    pub engine: String,
    pub lifecycle: Lifecycle,
    pub session_connected: bool,
    pub username: String,
    pub active_client: String,
    pub playback: PlaybackStatus,
    pub track: Option<Track>,
    pub position_ms: u32,
    pub volume: u16,
    pub shuffle: bool,
    pub repeat: RepeatMode,
    pub generation: u64,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error_code: String,
    pub error: String,
    /// Who holds the account's Connect session, as a person would name it:
    /// "this computer", another device's name and kind, or empty for nobody.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub session_holder: String,
    #[serde(skip)]
    pub seek_sequence: u64,
}

impl Default for BackendState {
    fn default() -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            backend_version: env!("CARGO_PKG_VERSION").to_string(),
            engine: "librespot".to_string(),
            lifecycle: Lifecycle::Starting,
            session_connected: false,
            username: String::new(),
            active_client: String::new(),
            playback: PlaybackStatus::Stopped,
            track: None,
            position_ms: 0,
            volume: 0,
            shuffle: false,
            repeat: RepeatMode::Off,
            generation: 0,
            error_code: String::new(),
            error: String::new(),
            session_holder: String::new(),
            seek_sequence: 0,
        }
    }
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct ProtocolError {
    pub code: String,
    pub message: String,
}

impl ProtocolError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage<'a> {
    Response {
        v: u16,
        id: u64,
        ok: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        result: Option<serde_json::Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<ProtocolError>,
    },
    Event {
        v: u16,
        event: &'a str,
        state: &'a BackendState,
    },
}

impl<'a> ServerMessage<'a> {
    pub fn success(id: u64, result: serde_json::Value) -> Self {
        Self::Response {
            v: PROTOCOL_VERSION,
            id,
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn failure(id: u64, error: ProtocolError) -> Self {
        Self::Response {
            v: PROTOCOL_VERSION,
            id,
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_is_flat_and_versioned() {
        let request: Request =
            serde_json::from_str(r#"{"v":1,"id":7,"command":"seek","position_ms":1234}"#).unwrap();
        assert_eq!(request.v, PROTOCOL_VERSION);
        assert_eq!(request.id, 7);
        assert_eq!(request.command, Command::Seek { position_ms: 1234 });
    }

    #[test]
    fn load_defaults_to_playing() {
        let request: Request =
            serde_json::from_str(r#"{"v":1,"id":1,"command":"load","uris":["spotify:track:abc"]}"#)
                .unwrap();
        let Command::Load { play, .. } = request.command else {
            panic!("expected load command");
        };
        assert!(play);
    }

    #[test]
    fn state_event_has_stable_envelope() {
        let state = BackendState::default();
        let value = serde_json::to_value(ServerMessage::Event {
            v: PROTOCOL_VERSION,
            event: "state_changed",
            state: &state,
        })
        .unwrap();
        assert_eq!(value["type"], "event");
        assert_eq!(value["v"], 1);
        assert_eq!(value["state"]["engine"], "librespot");
        assert!(value["state"].get("error_code").is_none());
        assert!(value["state"].get("seek_sequence").is_none());
    }

    #[test]
    fn state_event_includes_machine_readable_errors() {
        let state = BackendState {
            error_code: "audio_key_unavailable".to_string(),
            error: "Try another Spotify Connect device".to_string(),
            ..BackendState::default()
        };
        let value = serde_json::to_value(ServerMessage::Event {
            v: PROTOCOL_VERSION,
            event: "state_changed",
            state: &state,
        })
        .unwrap();

        assert_eq!(value["state"]["error_code"], "audio_key_unavailable");
        assert_eq!(value["state"]["error"], state.error);
    }
}
