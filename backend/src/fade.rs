use std::{
    sync::{Arc, Mutex, MutexGuard, PoisonError},
    time::Duration,
};

use librespot_playback::{
    NUM_CHANNELS, SAMPLE_RATE,
    audio_backend::{Sink, SinkResult},
    convert::Converter,
    decoder::AudioPacket,
};
use tokio::sync::watch;

// 200 ms.
pub const FADE_FRAMES: usize = SAMPLE_RATE as usize * 200 / 1000;
// Stop waiting for a fade if the player is not sending audio.
const FADE_TIMEOUT: Duration = Duration::from_secs(1);
// Bring the sound back if the pause that should follow a fade never lands.
const SILENCE_LIMIT_FRAMES: usize = SAMPLE_RATE as usize * 2;

// Ramps the volume of everything the player writes, for soft pauses and resumes.
#[derive(Clone)]
pub struct Fader(Arc<Shared>);

struct Shared {
    ramp: Mutex<Ramp>,
    silent: watch::Sender<bool>,
}

struct Ramp {
    level: usize,
    rising: bool,
    fade_in_next_start: bool,
    silent_frames: usize,
}

impl Default for Fader {
    fn default() -> Self {
        Self(Arc::new(Shared {
            ramp: Mutex::new(Ramp {
                level: FADE_FRAMES,
                rising: true,
                fade_in_next_start: false,
                silent_frames: 0,
            }),
            silent: watch::Sender::new(false),
        }))
    }
}

impl Fader {
    pub fn wrap(&self, inner: Box<dyn Sink>) -> Box<dyn Sink> {
        Box::new(FadingSink {
            inner,
            fader: self.clone(),
        })
    }

    pub fn fade_in_next_start(&self) {
        self.ramp().fade_in_next_start = true;
    }

    pub async fn fade_out(&self) {
        let mut silent = {
            let mut ramp = self.ramp();
            ramp.rising = false;
            ramp.silent_frames = 0;
            self.0.silent.send_replace(false);
            self.0.silent.subscribe()
        };
        let _ = tokio::time::timeout(FADE_TIMEOUT, silent.wait_for(|silent| *silent)).await;
    }

    fn ramp(&self) -> MutexGuard<'_, Ramp> {
        self.0.ramp.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl Ramp {
    // Returns true while a fade out has gone quiet.
    fn apply(&mut self, samples: &mut [f64]) -> bool {
        if self.rising && self.level == FADE_FRAMES {
            return false;
        }
        for frame in samples.chunks_mut(NUM_CHANNELS as usize) {
            self.level = if self.rising {
                (self.level + 1).min(FADE_FRAMES)
            } else {
                self.level.saturating_sub(1)
            };
            let gain = self.level as f64 / FADE_FRAMES as f64;
            frame.iter_mut().for_each(|sample| *sample *= gain);
        }
        if self.rising || self.level > 0 {
            return false;
        }
        self.silent_frames += samples.len() / NUM_CHANNELS as usize;
        if self.silent_frames > SILENCE_LIMIT_FRAMES {
            self.rising = true;
        }
        true
    }
}

struct FadingSink {
    inner: Box<dyn Sink>,
    fader: Fader,
}

impl Sink for FadingSink {
    fn start(&mut self) -> SinkResult<()> {
        self.inner.start()?;
        let mut ramp = self.fader.ramp();
        let fade_in = std::mem::take(&mut ramp.fade_in_next_start);
        ramp.level = if fade_in { 0 } else { FADE_FRAMES };
        ramp.rising = true;
        Ok(())
    }

    fn stop(&mut self) -> SinkResult<()> {
        self.inner.stop()
    }

    fn write(&mut self, mut packet: AudioPacket, converter: &mut Converter) -> SinkResult<()> {
        if let AudioPacket::Samples(samples) = &mut packet
            && self.fader.ramp().apply(samples)
        {
            self.fader.0.silent.send_replace(true);
        }
        self.inner.write(packet, converter)
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use std::sync::{Arc, Mutex};

    use librespot_playback::{
        NUM_CHANNELS,
        audio_backend::{Sink, SinkResult},
        convert::Converter,
        decoder::AudioPacket,
    };

    const PACKET_FRAMES: usize = 1024;

    #[derive(Clone, Default)]
    pub struct Recorder(Arc<Mutex<Vec<f64>>>);

    impl Recorder {
        // One value per frame, after checking both channels match.
        pub fn frames(&self) -> Vec<f64> {
            let samples = self.0.lock().unwrap();
            samples
                .chunks(NUM_CHANNELS as usize)
                .map(|frame| {
                    assert!(frame.iter().all(|sample| *sample == frame[0]));
                    frame[0]
                })
                .collect()
        }
    }

    impl Sink for Recorder {
        fn write(&mut self, packet: AudioPacket, _: &mut Converter) -> SinkResult<()> {
            let mut samples = self.0.lock().unwrap();
            samples.extend_from_slice(packet.samples().unwrap());
            Ok(())
        }
    }

    pub fn write_frames(sink: &mut dyn Sink, frames: usize) {
        let mut converter = Converter::new(None);
        for _ in 0..frames.div_ceil(PACKET_FRAMES) {
            let packet = vec![1.0; PACKET_FRAMES * NUM_CHANNELS as usize];
            sink.write(AudioPacket::Samples(packet), &mut converter)
                .unwrap();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{testing::*, *};

    const FADE_200_MS: usize = SAMPLE_RATE as usize * 200 / 1000;

    fn started(fader: &Fader) -> (Box<dyn Sink>, Recorder) {
        let recorder = Recorder::default();
        let mut sink = fader.wrap(Box::new(recorder.clone()));
        sink.start().unwrap();
        (sink, recorder)
    }

    #[test]
    fn audio_is_untouched_until_a_fade_starts() {
        let (mut sink, recorder) = started(&Fader::default());
        write_frames(sink.as_mut(), 10);
        assert!(recorder.frames().iter().all(|gain| *gain == 1.0));
    }

    #[tokio::test]
    async fn fading_out_reaches_silence_after_200_ms() {
        let fader = Fader::default();
        let (mut sink, recorder) = started(&fader);
        let fading = tokio::spawn({
            let fader = fader.clone();
            async move { fader.fade_out().await }
        });
        tokio::task::yield_now().await;
        assert!(!fading.is_finished());

        write_frames(sink.as_mut(), FADE_200_MS + 2048);
        fading.await.unwrap();
        let frames = recorder.frames();
        assert!(frames[0] < 1.0 && frames[0] > 0.99);
        assert!((frames[FADE_200_MS / 2] - 0.5).abs() < 0.01);
        assert!(frames[FADE_200_MS - 1..].iter().all(|gain| *gain == 0.0));
    }

    #[tokio::test]
    async fn fading_out_gives_up_when_no_audio_is_flowing() {
        let fader = Fader::default();
        let _sink = started(&fader);
        tokio::time::timeout(std::time::Duration::from_secs(2), fader.fade_out())
            .await
            .expect("waited forever for audio that never came");
    }

    #[test]
    fn a_resume_fades_back_in_from_silence() {
        let fader = Fader::default();
        fader.fade_in_next_start();
        let (mut sink, recorder) = started(&fader);
        write_frames(sink.as_mut(), FADE_200_MS + 2048);
        let frames = recorder.frames();
        assert!(frames[0] < 0.01);
        assert!((frames[FADE_200_MS / 2] - 0.5).abs() < 0.01);
        assert!(frames[FADE_200_MS - 1..].iter().all(|gain| *gain == 1.0));
    }

    #[tokio::test]
    async fn a_later_start_without_a_resume_plays_at_full_volume() {
        let fader = Fader::default();
        fader.fade_in_next_start();
        let (mut sink, _) = started(&fader);
        sink.stop().unwrap();
        let recorder = Recorder::default();
        let mut sink = fader.wrap(Box::new(recorder.clone()));
        sink.start().unwrap();
        write_frames(sink.as_mut(), 10);
        assert!(recorder.frames().iter().all(|gain| *gain == 1.0));
    }

    #[tokio::test]
    async fn sound_comes_back_if_the_pause_never_arrives() {
        let fader = Fader::default();
        let (mut sink, recorder) = started(&fader);
        let fading = tokio::spawn({
            let fader = fader.clone();
            async move { fader.fade_out().await }
        });
        tokio::task::yield_now().await;
        write_frames(sink.as_mut(), FADE_FRAMES);
        fading.await.unwrap();

        write_frames(sink.as_mut(), SAMPLE_RATE as usize * 3);
        assert_eq!(recorder.frames().last(), Some(&1.0));
    }
}
