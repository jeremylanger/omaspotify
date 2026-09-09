use std::{fs, io, os::unix::fs::PermissionsExt, path::PathBuf, sync::Arc};

use anyhow::{Context, Result};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::{Semaphore, watch},
};

/// The largest single request we will buffer. A load command carries a list of
/// track URIs, so this has room for tens of thousands of them; anything past it
/// is not a request we sent.
const MAX_FRAME_BYTES: usize = 1024 * 1024;

/// The player opens one connection. The rest of the allowance is slack.
const MAX_CLIENTS: usize = 8;

/// Reads newline-delimited requests without letting one grow without end.
///
/// `BufReader::lines()` will buffer whatever it is given, so a client that
/// never sends a newline can make the backend allocate until it dies. This
/// keeps the partial line in the struct rather than in the future, so it stays
/// safe to cancel inside `tokio::select!`, and refuses a frame over the cap
/// instead of growing to meet it.
struct BoundedLines<R> {
    reader: BufReader<R>,
    partial: Vec<u8>,
}

impl<R: AsyncRead + Unpin> BoundedLines<R> {
    fn new(reader: R) -> Self {
        Self {
            reader: BufReader::new(reader),
            partial: Vec::new(),
        }
    }

    /// `Ok(None)` at end of stream. An oversized frame is an error, because a
    /// sender that far outside the protocol has nothing more worth reading.
    async fn next_line(&mut self) -> Result<Option<String>, FrameError> {
        loop {
            let available = self.reader.fill_buf().await.map_err(FrameError::Io)?;
            if available.is_empty() {
                if self.partial.is_empty() {
                    return Ok(None);
                }
                let line = std::mem::take(&mut self.partial);
                return Ok(Some(String::from_utf8_lossy(&line).into_owned()));
            }
            if let Some(end) = available.iter().position(|byte| *byte == b'\n') {
                if self.partial.len() + end > MAX_FRAME_BYTES {
                    return Err(FrameError::TooLong);
                }
                self.partial.extend_from_slice(&available[..end]);
                self.reader.consume(end + 1);
                let mut line = std::mem::take(&mut self.partial);
                if line.last() == Some(&b'\r') {
                    line.pop();
                }
                return Ok(Some(String::from_utf8_lossy(&line).into_owned()));
            }
            if self.partial.len() + available.len() > MAX_FRAME_BYTES {
                return Err(FrameError::TooLong);
            }
            let taken = available.len();
            self.partial.extend_from_slice(available);
            self.reader.consume(taken);
        }
    }
}

#[derive(Debug)]
enum FrameError {
    Io(io::Error),
    TooLong,
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(f, "{error}"),
            Self::TooLong => write!(f, "request longer than {MAX_FRAME_BYTES} bytes"),
        }
    }
}

use crate::{
    engine::{EngineSender, send_with_reply},
    protocol::{PROTOCOL_VERSION, ProtocolError, Request, ServerMessage},
    state::StateStore,
};

pub struct SocketGuard {
    path: PathBuf,
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

pub async fn serve(
    path: PathBuf,
    state: StateStore,
    commands: EngineSender,
    mut shutdown: watch::Receiver<bool>,
) -> Result<SocketGuard> {
    let parent = path
        .parent()
        .context("backend socket path has no parent directory")?;
    fs::create_dir_all(parent)
        .with_context(|| format!("failed to create socket directory {}", parent.display()))?;
    if path.exists() {
        fs::remove_file(&path)
            .with_context(|| format!("failed to remove stale socket {}", path.display()))?;
    }

    let listener = UnixListener::bind(&path)
        .with_context(|| format!("failed to bind backend socket {}", path.display()))?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("failed to secure backend socket {}", path.display()))?;
    let guard = SocketGuard { path };

    let clients = Arc::new(Semaphore::new(MAX_CLIENTS));
    tokio::spawn(async move {
        loop {
            tokio::select! {
                accepted = listener.accept() => match accepted {
                    Ok((stream, _)) => {
                        // Refuse rather than queue: a caller holding connections
                        // open should not be able to grow our work list.
                        match Arc::clone(&clients).try_acquire_owned() {
                            Ok(permit) => {
                                tokio::spawn(handle_client(
                                    stream,
                                    state.clone(),
                                    commands.clone(),
                                    permit,
                                ));
                            }
                            Err(_) => {
                                log::warn!(
                                    "backend socket refused a client: {MAX_CLIENTS} already connected"
                                );
                                drop(stream);
                            }
                        }
                    }
                    Err(error) => {
                        log::warn!("backend socket accept failed: {error}");
                    }
                },
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
            }
        }
    });

    Ok(guard)
}

async fn handle_client(
    stream: UnixStream,
    state: StateStore,
    commands: EngineSender,
    permit: tokio::sync::OwnedSemaphorePermit,
) {
    if let Err(error) = client_loop(stream, state, commands).await {
        log::debug!("backend client disconnected: {error}");
    }
    drop(permit);
}

async fn client_loop(stream: UnixStream, state: StateStore, commands: EngineSender) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BoundedLines::new(reader);
    let mut states = state.subscribe();
    let initial = state.with(|snapshot| {
        encode_message(&ServerMessage::Event {
            v: PROTOCOL_VERSION,
            event: "state_changed",
            state: snapshot,
        })
    })?;
    write_encoded(&mut writer, &initial).await?;

    loop {
        tokio::select! {
            line = lines.next_line() => {
                let line = match line {
                    Ok(Some(line)) => line,
                    Ok(None) => break,
                    Err(FrameError::TooLong) => {
                        log::warn!("backend client sent an oversized request; closing");
                        let refusal = ServerMessage::failure(
                            0,
                            ProtocolError::new(
                                "request_too_large",
                                format!("request longer than {MAX_FRAME_BYTES} bytes"),
                            ),
                        );
                        let _ = write_message(&mut writer, &refusal).await;
                        break;
                    }
                    Err(FrameError::Io(error)) => return Err(error.into()),
                };
                let message = handle_line(&line, &state, &commands).await;
                write_message(&mut writer, &message).await?;
            }
            changed = states.changed() => {
                if changed.is_err() { break; }
                let encoded = {
                    let snapshot = states.borrow_and_update();
                    encode_message(&ServerMessage::Event {
                        v: PROTOCOL_VERSION,
                        event: "state_changed",
                        state: &snapshot,
                    })?
                };
                write_encoded(&mut writer, &encoded).await?;
            }
        }
    }
    Ok(())
}

async fn handle_line<'a>(
    line: &str,
    state: &StateStore,
    commands: &EngineSender,
) -> ServerMessage<'a> {
    let request: Request = match serde_json::from_str(line) {
        Ok(request) => request,
        Err(error) => {
            return ServerMessage::failure(
                0,
                ProtocolError::new("invalid_request", format!("invalid JSON request: {error}")),
            );
        }
    };
    if request.v != PROTOCOL_VERSION {
        return ServerMessage::failure(
            request.id,
            ProtocolError::new(
                "unsupported_version",
                format!(
                    "protocol version {} is unsupported; expected {}",
                    request.v, PROTOCOL_VERSION
                ),
            ),
        );
    }

    let result = match request.command {
        crate::protocol::Command::Hello => Ok(serde_json::json!({
            "protocol_version": PROTOCOL_VERSION,
            "backend_version": env!("CARGO_PKG_VERSION"),
            "engine": "librespot"
        })),
        crate::protocol::Command::Ping => Ok(serde_json::json!({ "pong": true })),
        crate::protocol::Command::GetState => state
            .with(|snapshot| serde_json::to_value(snapshot))
            .map_err(|error| ProtocolError::new("serialization_error", error.to_string())),
        command => send_with_reply(commands, command).await,
    };

    match result {
        Ok(value) => ServerMessage::success(request.id, value),
        Err(error) => ServerMessage::failure(request.id, error),
    }
}

async fn write_message(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    message: &ServerMessage<'_>,
) -> Result<()> {
    let encoded = encode_message(message)?;
    write_encoded(writer, &encoded).await
}

fn encode_message(message: &ServerMessage<'_>) -> Result<Vec<u8>> {
    let mut encoded = serde_json::to_vec(message).context("failed to encode backend message")?;
    encoded.push(b'\n');
    Ok(encoded)
}

async fn write_encoded(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    encoded: &[u8],
) -> Result<()> {
    writer
        .write_all(encoded)
        .await
        .context("failed to write backend message")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn reads_whole_lines_and_stops_at_the_end() {
        let input: &[u8] = b"one\ntwo\r\nthree";
        let mut lines = BoundedLines::new(input);
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "one");
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "two");
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "three");
        assert!(lines.next_line().await.unwrap().is_none());
    }

    // A client that never sends a newline used to make us allocate until we died.
    #[tokio::test]
    async fn refuses_a_frame_past_the_cap() {
        let flood = vec![b'x'; MAX_FRAME_BYTES + 1];
        let mut lines = BoundedLines::new(flood.as_slice());
        assert!(matches!(lines.next_line().await, Err(FrameError::TooLong)));
    }

    #[tokio::test]
    async fn accepts_a_frame_right_up_to_the_cap() {
        let mut framed = vec![b'x'; MAX_FRAME_BYTES];
        framed.push(b'\n');
        let mut lines = BoundedLines::new(framed.as_slice());
        let line = lines.next_line().await.unwrap().unwrap();
        assert_eq!(line.len(), MAX_FRAME_BYTES);
    }

    // The cap is on one frame, not on the connection: a long-lived client keeps
    // sending commands.
    #[tokio::test]
    async fn many_small_frames_are_fine() {
        let mut input = Vec::new();
        for _ in 0..1000 {
            input.extend_from_slice(b"{\"v\":1,\"id\":1,\"command\":\"ping\"}\n");
        }
        let mut lines = BoundedLines::new(input.as_slice());
        let mut seen = 0;
        while lines.next_line().await.unwrap().is_some() {
            seen += 1;
        }
        assert_eq!(seen, 1000);
    }
}
