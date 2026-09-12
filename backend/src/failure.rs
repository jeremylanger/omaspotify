use std::{
    fmt, fs,
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone, Copy)]
pub enum Failure {
    InvalidConfiguration,
    MissingCredentials,
    ReconnectExhausted,
    Transient,
}
impl Failure {
    pub fn code(self) -> &'static str {
        match self {
            Self::InvalidConfiguration => "invalid_configuration",
            Self::MissingCredentials => "missing_credentials",
            Self::ReconnectExhausted => "reconnect_exhausted",
            Self::Transient => "connection_failed",
        }
    }
    pub fn exit_code(self) -> u8 {
        match self {
            Self::InvalidConfiguration => 78,
            Self::MissingCredentials => 77,
            Self::ReconnectExhausted => 75,
            Self::Transient => 1,
        }
    }
}
impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.code())
    }
}
impl std::error::Error for Failure {}

pub fn record(socket: &Path, failure: Failure) -> std::io::Result<()> {
    let parent = socket
        .parent()
        .ok_or_else(|| std::io::Error::other("missing runtime directory"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!("startup-error.{}.tmp", std::process::id()));
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary)?;
    let result = (|| {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        writeln!(
            file,
            "{}",
            serde_json::json!({"code": failure.code(), "timestamp": timestamp})
        )?;
        file.sync_all()?;
        fs::rename(&temporary, parent.join("startup-error.json"))
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

pub fn clear(socket: &Path) {
    if let Some(parent) = socket.parent() {
        let _ = fs::remove_file(parent.join("startup-error.json"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    #[test]
    fn diagnostic_is_private_and_contains_only_safe_fields() {
        let directory =
            std::env::temp_dir().join(format!("spotify-failure-test-{}", std::process::id()));
        let socket = directory.join("backend.sock");
        record(&socket, Failure::MissingCredentials).unwrap();
        let path = directory.join("startup-error.json");
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let value: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(value["code"], "missing_credentials");
        assert_eq!(value.as_object().unwrap().len(), 2);
        clear(&socket);
        fs::remove_dir(directory).unwrap();
    }
}
