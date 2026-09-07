use std::{env, fs, path::PathBuf};

use anyhow::{Context, Result, bail};
use librespot_playback::config::Bitrate;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Default)]
struct ConfigFile {
    #[serde(default)]
    global: GlobalConfig,
}

#[derive(Clone, Debug, Deserialize, Default)]
struct GlobalConfig {
    device_name: Option<String>,
    bitrate: Option<u16>,
    autoplay: Option<bool>,
    backend: Option<String>,
    device: Option<String>,
    no_audio_cache: Option<bool>,
    max_cache_size: Option<u64>,
    cache_path: Option<PathBuf>,
    normalisation: Option<bool>,
    normalisation_pregain_db: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct BackendConfig {
    pub device_name: String,
    pub bitrate: Bitrate,
    pub bitrate_kbps: u16,
    pub autoplay: bool,
    pub normalisation: bool,
    pub normalisation_pregain_db: f64,
    pub audio_device: Option<String>,
    pub audio_cache: bool,
    pub max_cache_size: Option<u64>,
    pub cache_root: PathBuf,
    pub credentials_root: PathBuf,
}

#[derive(Clone, Debug, Serialize)]
pub struct ConfigSummary<'a> {
    pub device_name: &'a str,
    pub bitrate_kbps: u16,
    pub autoplay: bool,
    pub normalisation: bool,
    pub normalisation_pregain_db: f64,
    pub audio_cache: bool,
    pub max_cache_size: Option<u64>,
    pub cache_root: &'a std::path::Path,
    pub credentials_root: &'a std::path::Path,
}

impl BackendConfig {
    pub fn load(path: &std::path::Path) -> Result<Self> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("failed to read configuration at {}", path.display()))?;
        let parsed: ConfigFile = toml::from_str(&content)
            .with_context(|| format!("failed to parse configuration at {}", path.display()))?;
        let global = parsed.global;

        let device_name = global
            .device_name
            .unwrap_or_else(|| "OmaSpotify".to_string());
        let device_name = device_name.trim().to_string();
        if device_name.is_empty()
            || device_name.len() > 64
            || device_name.chars().any(char::is_control)
        {
            bail!("device_name must contain 1 to 64 printable characters");
        }

        let bitrate_kbps = global.bitrate.unwrap_or(320);
        let bitrate = match bitrate_kbps {
            96 => Bitrate::Bitrate96,
            160 => Bitrate::Bitrate160,
            320 => Bitrate::Bitrate320,
            value => bail!("unsupported bitrate {value}; expected 96, 160, or 320"),
        };

        // Matches Spotify's Loud/Normal/Quiet levels, which sit within a few dB
        // of each other. Anything wider is a mistake, not a preference.
        let normalisation_pregain_db = global.normalisation_pregain_db.unwrap_or(0.0);
        if !normalisation_pregain_db.is_finite()
            || !(-15.0..=15.0).contains(&normalisation_pregain_db)
        {
            bail!("normalisation_pregain_db must be between -15 and 15");
        }

        let backend = global.backend.unwrap_or_else(|| "pulseaudio".to_string());
        if backend != "pulseaudio" {
            bail!("unsupported audio backend {backend:?}; expected \"pulseaudio\"");
        }

        let cache_root = global.cache_path.unwrap_or_else(default_cache_root);
        let credentials_root = default_credentials_root();

        Ok(Self {
            device_name,
            bitrate,
            bitrate_kbps,
            autoplay: global.autoplay.unwrap_or(true),
            normalisation: global.normalisation.unwrap_or(true),
            normalisation_pregain_db,
            audio_device: global.device.filter(|value| !value.trim().is_empty()),
            audio_cache: !global.no_audio_cache.unwrap_or(false),
            max_cache_size: global.max_cache_size.or(Some(1_000_000_000)),
            cache_root,
            credentials_root,
        })
    }

    pub fn summary(&self) -> ConfigSummary<'_> {
        ConfigSummary {
            device_name: &self.device_name,
            bitrate_kbps: self.bitrate_kbps,
            autoplay: self.autoplay,
            normalisation: self.normalisation,
            normalisation_pregain_db: self.normalisation_pregain_db,
            audio_cache: self.audio_cache,
            max_cache_size: self.max_cache_size,
            cache_root: &self.cache_root,
            credentials_root: &self.credentials_root,
        }
    }
}

pub fn default_config_path() -> PathBuf {
    config_home().join("omaspotify/playback.conf")
}

pub fn default_socket_path() -> PathBuf {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc_getuid() })));
    runtime.join("omaspotify/backend.sock")
}

fn config_home() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .unwrap_or_else(|| PathBuf::from(".config"))
}

fn default_cache_root() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .unwrap_or_else(|| PathBuf::from(".cache"))
        .join("omaspotify/audio")
}

fn default_credentials_root() -> PathBuf {
    env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .unwrap_or_else(|| PathBuf::from(".local/state"))
        .join("omaspotify")
}

#[cfg(unix)]
unsafe fn libc_getuid() -> u32 {
    unsafe extern "C" {
        fn getuid() -> u32;
    }
    unsafe { getuid() }
}

#[cfg(not(unix))]
unsafe fn libc_getuid() -> u32 {
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn write_config(name: &str, body: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("omaspotify-{name}-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("playback.conf");
        let mut file = fs::File::create(&path).unwrap();
        writeln!(file, "{body}").unwrap();
        path
    }

    #[test]
    fn audio_cache_lives_under_our_own_name() {
        let root = default_cache_root();
        assert!(root.ends_with("omaspotify/audio"), "got {}", root.display());
    }

    #[test]
    fn normalisation_is_on_by_default_at_the_published_target() {
        let path = write_config("norm-default", "[global]\ndevice_name=\"D\"");
        let config = BackendConfig::load(&path).unwrap();
        assert!(config.normalisation);
        assert_eq!(config.normalisation_pregain_db, 0.0);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn normalisation_can_be_turned_off() {
        let path = write_config("norm-off", "[global]\nnormalisation=false");
        let config = BackendConfig::load(&path).unwrap();
        assert!(!config.normalisation);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn pregain_carries_the_chosen_volume_level() {
        for (body, expected) in [("3", 3.0), ("-5", -5.0), ("0", 0.0)] {
            let path = write_config(
                &format!("pregain{body}"),
                &format!("[global]\nnormalisation_pregain_db={body}"),
            );
            let config = BackendConfig::load(&path).unwrap();
            assert_eq!(config.normalisation_pregain_db, expected);
            fs::remove_file(path).unwrap();
        }
    }

    #[test]
    fn pregain_outside_a_sane_range_is_rejected() {
        let path = write_config("pregain-wild", "[global]\nnormalisation_pregain_db=40");
        assert!(BackendConfig::load(&path).is_err());
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn reads_existing_spotifyd_shape() {
        let dir =
            std::env::temp_dir().join(format!("omaspotify-config-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("playback.conf");
        let mut file = fs::File::create(&path).unwrap();
        writeln!(
            file,
            "[global]\ndevice_name=\"Test Device\"\nbackend=\"pulseaudio\"\nbitrate=320\nautoplay=true\nno_audio_cache=false\nmax_cache_size=42"
        )
        .unwrap();

        let config = BackendConfig::load(&path).unwrap();
        assert_eq!(config.device_name, "Test Device");
        assert_eq!(config.bitrate_kbps, 320);
        assert!(config.audio_cache);
        assert_eq!(config.max_cache_size, Some(42));
        fs::remove_file(path).unwrap();
        fs::remove_dir(dir).unwrap();
    }
}
