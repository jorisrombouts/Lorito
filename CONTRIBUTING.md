# Contributing

Bug reports and pull requests are welcome.

- Build and run: `./build-app.sh`. It needs the macOS 26 SDK from the Xcode Command Line Tools; Xcode itself is not required.
- Before a pull request: `./check.sh` passes, and you have tried the change in the app.
- `AGENTS.md` has the rules that keep a change from breaking the app: permissions, the audio path, the cleanup prompt, the overlay. Read the section for the part you touch.
- Keep it small. Lorito does one thing; a feature that needs a new settings page is probably out of scope. Open an issue first to ask.
- A change a user notices gets one line under Unreleased in `CHANGELOG.md`.

By contributing you agree that your work is released under the MIT license in `LICENSE`.
