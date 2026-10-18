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
