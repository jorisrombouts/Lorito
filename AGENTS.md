# Lorito: rules for changing the code

What it is, how to install and use it: `README.md`. This file is what keeps a change from breaking the app.

## Docs

- After a change, check `README.md` and this file; rewrite only a sentence the change made wrong. Replace and delete before adding; no history, no changelog, no rationale a user does not need. The README's size and speed figures are measurements (`wc -l Sources/Lorito/*.swift`, `du -sh` on the installed binary, the log); a code change re-measures them.

## Build and test

- `./build-app.sh` builds release, signs, and restarts `build/Lorito.app`. `./build-app.sh install` refreshes `/Applications/Lorito.app`, the login item. Never replace a bundle under a running app: macOS silently drops its permissions. Never run both copies at once.
- Sign with the "Lorito Dev" certificate (`make-signing-cert.sh`). An ad-hoc signature is a new identity per build, and every permission grant dies with it.
- `./check.sh` is the smoke test: engine on English, Dutch, noise, a hum it must hear no speech in and a spoken "thank you" it must keep; cleanup on Dutch and on a question it must not answer; overlay render. Run it before merging. The paste, hotkey and hands-free paths are checked by hand; `--insert-test` pastes into the frontmost app and the log's `mode=` field shows the gesture.
- Log: `~/Library/Logs/Lorito.log`. Baseline on an M4 Pro: engine load 0.1 to 0.2 s (12 s on the first launch of a new build while Core ML compiles the models, plus the download the first time ever), recognition 0.05 to 0.2 s per dictation, cleanup 0.3 s plus 25 ms per second of audio. Far above these is a regression.
- The models live in `~/Library/Application Support/FluidAudio`, downloaded by FluidAudio from Hugging Face on first launch; "engine failed" in the log with the menu showing the reason means that download did not land. FluidAudio's API is the source in `.build/checkouts/FluidAudio`; docs.fluidinference.com lags it by several versions.

## Permissions

- A paste that does not land is Accessibility, not code: `TextInserter.insert` returns the reason and the pill shows it instead of "Inserted". `ax_trusted=0` in the log with the app enabled in System Settings means a stale entry: `tccutil reset Accessibility nl.joris.lorito`, relaunch, grant again. A binary started from a shell inherits the terminal's grants; only `open` tests the app's own.
- The agent sandbox cannot read `log show` or take screenshots. Use the log file and `--overlay-demo`.

## Code

- SwiftUI instantiates the `App` struct more than once: the controller is a singleton, started on `didFinishLaunching`.
- Top-level `Task {}` in `main.swift` runs on the main actor; blocking main with a semaphore deadlocks it. Harness code uses `RunLoop.main.run()` or `Task.detached`.
- Recording uses `AVCaptureSession` with an explicit `AVCaptureDeviceInput`; `AVAudioEngine` cannot bind a device reliably (Bluetooth headsets renegotiate their sample rate right after the mic opens). The converter is rebuilt when the buffer format changes.
- The level meter in `DictationController` starts fresh per dictation and tracks a noise floor from the quiet band only and a recent peak, with tuned constants; recorded silence must give zero. A floor that follows everything below the peak locks onto the voice once a key click has set the peak, and the bars stay at zero.
- Parakeet returns empty text for noise, hum and clicks on its own, with no VAD in front of it; `check.sh` holds that. A fresh `TdtDecoderState` per dictation keeps one dictation from leaking into the next.
- FoundationModels wants to answer a dictated question and translate a foreign one; the instructions forbid both, and the examples carried as past turns in the session `Transcript` show it. Write every example the way the engine hands text over, punctuated and capitalised: lowercase examples teach the model that tidy-looking input needs no edit, and it hands a filler-ridden sentence straight back. It applies a marked self-correction ("no wait") reliably and an unmarked restart ("What, why") in neither direction, inventing ungrammatical text when pushed, so the prompt leaves those alone. Never use the same text as an example and a test; a duplicate prompt makes the model answer it. Verify with `--clean`.
- The cleanup session is rebuilt and prewarmed when recording starts: macOS evicts the model after idle, and a cold call takes over 2 s, past the timeout, which reaches the pill as "Raw text inserted".
- Overlay: the `NSPanel` has a fixed generous transparent frame and never activates; the SwiftUI pill is a Liquid Glass capsule (`glassEffect`) that sizes itself inside it, and the hands-free ✕ is a tap gesture, not a button. `ProgressView` does not render in a non-activating panel. `--overlay-demo` renders through an `NSHostingView` because `ImageRenderer` drops a glass-effect view; the glass itself never appears offscreen, so judge the capsule on screen. The app icon, the menu bar glyph and the pill's parrot are one drawing, `LoritoApp.parrot`: `build-app.sh` renders the icns from the binary (`--icon`), and the drawing samples its paths at 680 pt whatever the output size, because SwiftUI `Path.contains` flattens curves with an absolute tolerance and moves bar tops at 18 pt. The pill's parrot keeps the icon's colours and `isTemplate` off; the level bars are `Color.primary`, since a plain `.primary` fill turns vibrant white under glass. Every other icon is an SF Symbol, and the menu bar stays monochrome. Animations ignore Reduce Motion by design.
