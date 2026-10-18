# Changelog

Notable changes, newest first. Versions follow the GitHub releases.

## Unreleased

## 1.0.0 — 2026-10-18

First release.

- Hold Left Option and speak, or tap it and speak hands-free. The text is pasted at the cursor in any app.
- Recognition with NVIDIA parakeet-tdt-0.6b-v3 on the Neural Engine through FluidAudio: 25 European languages, detected automatically; silence and noise come back empty.
- Cleanup with Apple's on-device Foundation Models: punctuation, capitalisation, fillers, self-corrections such as "no wait". Never answers or translates; dictations under four words are inserted as is.
- Menu bar parrot drawn from the same shape as the app icon: a dot while listening, dimmed while working.
- Glass pill with the parrot and live level bars while listening; plain text for transcribing, cleaning up, inserted, or why a paste did not land.
- Menu: microphone picker, cleanup toggle, Launch at Login, last five transcriptions, Quit.
- Everything runs on the Mac. Nothing leaves it.

## Before 1.0

Pre-release history, first as LocalWhisper, then Lorito.

- 2026-09-07 — LocalWhisper: whisper.cpp recognition, Foundation Models cleanup, hold Left Option, pill, menu bar. Self-signed certificate for a stable identity, install mode with Launch at Login, cleanup timeout scaled to the clip, silence gate, `check.sh` smoke test.
- 2026-09-08 — Microphone picker. Recorder on AVCaptureSession with an explicit device, for Bluetooth headsets. Level meter with a noise floor and a decaying peak.
- 2026-09-10 — Hands-free mode: tap Left Option, Esc or ✕ discards, stops after two minutes without voice. Recent transcriptions in the menu, click copies.
- 2026-09-14 to 16 — Cleanup prewarmed when recording starts, examples carried as transcript turns, never answers a dictated question. Silero VAD in front of whisper. The pill reports a failed paste instead of Inserted.
- 2026-10-17 — Parakeet TDT v3 through FluidAudio replaces whisper and the VAD: 25 languages, detected automatically. Renamed to Lorito.
- 2026-10-18 — App icon, a parrot of waveform bars in system orange, and the menu bar glyph drawn from it. Pill rebuilt around the parrot in a glass capsule. Meter no longer freezes after a key click. Social preview.
