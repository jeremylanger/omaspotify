//! Names the device that holds the account's Connect session.
//!
//! Spotify lets one device per account be active. When another one takes
//! the session, librespot logs only "device became inactive"; the cluster
//! update that caused it carries every device's name, so this listener
//! reads the same stream (the dealer fans a URI out to every subscriber),
//! logs who holds the session whenever that changes, and publishes it in
//! the backend state for the plugin to show.

use futures_util::StreamExt;
use librespot_core::{Session, dealer::protocol::Message};
use librespot_protocol::connect::{Cluster, ClusterUpdate};
use tokio::sync::watch;

use crate::state::StateStore;

const CLUSTER_URI: &str = "hm://connect-state/v1/cluster";

/// Follows whichever session is current; a reconnect brings a new dealer,
/// so the subscription is made again on it.
pub async fn watch(mut sessions: watch::Receiver<Session>, state: StateStore) {
    loop {
        let session = sessions.borrow_and_update().clone();
        let mut updates = match session
            .dealer()
            .listen_for(CLUSTER_URI, Message::from_raw::<ClusterUpdate>)
        {
            Ok(updates) => updates,
            Err(error) => {
                log::warn!("not following the Connect session: {error}");
                if sessions.changed().await.is_err() {
                    return;
                }
                continue;
            }
        };
        let ours = session.device_id().to_string();
        loop {
            tokio::select! {
                update = updates.next() => match update {
                    Some(Ok(update)) => note(&update, &ours, &state),
                    Some(Err(error)) => log::debug!("unreadable cluster update: {error}"),
                    None => break,
                },
                changed = sessions.changed() => {
                    if changed.is_err() {
                        return;
                    }
                    break;
                }
            }
        }
    }
}

fn note(update: &ClusterUpdate, ours: &str, state: &StateStore) {
    let Some(cluster) = update.cluster.as_ref() else {
        return;
    };
    let holder = describe(cluster, ours);
    if state.with(|current| current.session_holder == holder) {
        return;
    }
    state.update(|current| {
        current.session_holder = holder.clone();
        true
    });
    if holder.is_empty() {
        log::info!("Connect session: no active device");
    } else {
        log::info!("Connect session: {holder}");
    }
}

/// The active device as a person would name it, empty when there is none.
pub fn describe(cluster: &Cluster, ours: &str) -> String {
    let active = cluster.active_device_id.as_str();
    if active.is_empty() {
        return String::new();
    }
    if active == ours {
        return "this computer".to_string();
    }
    let Some(info) = cluster.device.get(active) else {
        return format!("an unlisted device [{active}]");
    };
    let kind = format!("{:?}", info.device_type.enum_value_or_default()).to_lowercase();
    let make: Vec<&str> = [info.brand.as_str(), info.model.as_str()]
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect();
    let name = if info.name.is_empty() {
        "unnamed device"
    } else {
        info.name.as_str()
    };
    if make.is_empty() {
        format!("{name} ({kind})")
    } else {
        format!("{name} ({kind}, {})", make.join(" "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use librespot_protocol::{connect::DeviceInfo, devices::DeviceType};
    use protobuf::EnumOrUnknown;

    fn cluster(active: &str, devices: &[(&str, &str, &str, &str, DeviceType)]) -> Cluster {
        let mut cluster = Cluster {
            active_device_id: active.to_string(),
            ..Default::default()
        };
        for (id, name, brand, model, kind) in devices {
            cluster.device.insert(
                id.to_string(),
                DeviceInfo {
                    name: name.to_string(),
                    brand: brand.to_string(),
                    model: model.to_string(),
                    device_type: EnumOrUnknown::new(*kind),
                    ..Default::default()
                },
            );
        }
        cluster
    }

    #[test]
    fn the_holder_is_named_the_way_a_person_would() {
        let phones = [(
            "abc",
            "Fred's iPhone",
            "Apple",
            "iPhone",
            DeviceType::SMARTPHONE,
        )];
        assert_eq!(
            describe(&cluster("abc", &phones), "ours"),
            "Fred's iPhone (smartphone, Apple iPhone)"
        );
        let bare = [("abc", "Kitchen", "", "", DeviceType::SPEAKER)];
        assert_eq!(
            describe(&cluster("abc", &bare), "ours"),
            "Kitchen (speaker)"
        );
    }

    #[test]
    fn ourselves_and_nobody_are_special_cases() {
        assert_eq!(describe(&cluster("ours", &[]), "ours"), "this computer");
        assert_eq!(describe(&cluster("", &[]), "ours"), "");
        assert_eq!(
            describe(&cluster("2446506725", &[]), "ours"),
            "an unlisted device [2446506725]"
        );
    }
}
