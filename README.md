# Lorito

Hold Left Option and speak, or tap it and speak hands-free. The text appears at your cursor, in any app.

- Recognition: NVIDIA's [parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (CC-BY-4.0) through [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0) on the Neural Engine. 25 European languages, detected automatically; silence and noise come back empty.
- Cleanup: Apple's on-device Foundation Models, the Apple Intelligence system model of about 3B parameters, not bundled.

Everything runs on your Mac. Nothing leaves it.

## Requirements

- Apple Silicon Mac running macOS 26
- Xcode Command Line Tools: `xcode-select --install`
- Apple Intelligence enabled, for the cleanup step. The app works without it and inserts the raw transcript.

## Install

```sh
git clone https://github.com/jorisrombouts/Lorito.git && cd Lorito
./build-app.sh install
```

The first launch downloads the recognition models, 461 MB, into `~/Library/Application Support/FluidAudio` and compiles them for the Neural Engine, about 12 s in all, during which the menu bar icon is there but dictation is not. Later launches load them in under a second. The app is installed in `/Applications` and appears in the menu bar as a waveform.
macOS asks for two permissions on first use: Microphone, and Accessibility, which is what lets the app paste at your cursor.

Upgrading from an install named `lorito`, lowercase: quit it, run `tccutil reset All nl.joris.lorito`, delete `/Applications/lorito.app`, then install as above and grant the two permissions again. If you made a signing certificate, run `./make-signing-cert.sh` again; it is now called "Lorito Dev", and the old "lorito Dev" can be deleted in Keychain Access.

## Use

Two ways, same result:

- **Hold** Left Option, speak, release.
- **Tap** Left Option, speak, tap again. Esc or the ✕ in the pill discards. It stops by itself after two minutes without speech.

Any other key while holding cancels, so Option shortcuts like `€` or `@` still work. A pill at the bottom of the screen shows listening, transcribing, cleaning up, and inserted, or the reason a paste did not land. The language is detected automatically; Dutch and English are verified.

The menu has a microphone picker ("Automatic" is the built-in microphone; Bluetooth headsets work when picked but miss the first half second), a cleanup toggle, Launch at Login, Recent transcriptions (the last five; clicking one copies it), and Quit.

Cleanup fixes punctuation and capitalisation, removes fillers, and applies self-corrections such as "no wait". It never translates. Dictations under four words are inserted as is.

## Speed

Measured on an M4 Pro, from key release to text at the cursor. Timings for your own machine are in the log, see Troubleshooting.

| Dictation | Recognition | Cleanup | Total |
|---|---|---|---|
| 3 s | 0.05 s | 0.3 s | 0.35 s |
| 6 s | 0.07 s | 0.4 s | 0.5 s |
| 10 s | 0.2 s | 0.7 s | 0.9 s |
| 22 s | 0.1 s | 0.7 s | 0.85 s |

Cleanup is nearly all of the wait. Turning it off in the menu leaves only the recognition column.

## Size

| Component | Size |
|---|---|
| Recognition models, in Application Support | 461 MB |
| App binary, FluidAudio linked in | 18 MB |
| App icon | 1.2 MB |

The Swift source is about 733 lines in 10 files.

## Privacy

One download of the recognition models on first launch, no other network calls. The models and Apple Intelligence run on-device. Your clipboard is restored after the paste.

## Troubleshooting

- The pill says "Accessibility permission missing": grant it in System Settings. If it is already enabled there, the entry is stale: run `tccutil reset Accessibility nl.joris.lorito`, relaunch the app, grant it again. The transcript is still in Recent transcriptions.
- Timings per dictation are in `~/Library/Logs/Lorito.log`.
- If you rebuild often, run `./make-signing-cert.sh` once so permissions survive rebuilds.

## Development

A Swift Package with no Xcode project; FluidAudio is its one dependency. `./build-app.sh` builds and runs `build/Lorito.app`. `./check.sh` is the smoke test. The rules for changing the code are in `AGENTS.md`.
