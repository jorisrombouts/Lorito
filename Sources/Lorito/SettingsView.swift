import AppKit
import SwiftUI

/// Lorito › Settings… (⌘,): the standard toolbar-tab window, each pane a grouped Form like System Settings.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            AboutPane().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
        .tint(.orange)
    }
}

struct GeneralPane: View {
    private let controller = DictationController.shared
    @AppStorage(Settings.hotkeyKey) private var hotkey = Hotkey.leftOption
    @AppStorage(Settings.inputDeviceKey) private var inputDevice = ""
    @AppStorage(Settings.cleanupEnabledKey) private var cleanupEnabled = true
    @AppStorage(Settings.polishEnabledKey) private var polishEnabled = false
    @AppStorage(Settings.soundsKey) private var sounds = false
    @AppStorage("launchAtLoginShown") private var launchAtLogin = false   // mirrors SMAppService; @State needs a macro plugin the Command Line Tools lack

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: $hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.name).tag($0) }
                }
            } footer: {
                Text(hotkey == .fn
                     ? "Hold to talk, or tap to talk hands-free. In Keyboard settings, set “Press 🌐 key to” to “Do Nothing”."
                     : "Hold to talk, or tap to talk hands-free. Pressing another key while holding cancels.")
                    .settingsFooter()
            }

            Section {
                Picker("Microphone", selection: $inputDevice) {
                    Text("Automatic (built-in)").tag("")
                    ForEach(AudioRecorder.inputDevices(), id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
            } footer: {
                Text("Bluetooth headsets work, but miss the first half second.").settingsFooter()
            }

            Section {
                Toggle("Clean up with Apple Intelligence", isOn: $cleanupEnabled)
                    .disabled(controller.cleanupUnavailable != nil)
            } footer: {
                Text(controller.cleanupUnavailable
                     ?? "Fixes punctuation, drops filler words and applies corrections like “no wait”. Never translates or answers. Off inserts exactly what was heard.")
                    .settingsFooter()
            }

            Section {
                Toggle("Tidy up the whole text", isOn: cleanupEnabled ? $polishEnabled : .constant(false))
                    .disabled(!cleanupEnabled || controller.cleanupUnavailable != nil)
            } footer: {
                Text("Reads the cleaned text once more as a whole and removes leftovers: repeated phrases, false starts, stray fillers. Never changes or adds a word. Takes a moment longer.")
                    .settingsFooter()
            }

            Section {
                Toggle("Play sounds", isOn: $sounds)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        guard on != Settings.launchAtLogin else { return }
                        Settings.launchAtLogin = on
                        launchAtLogin = Settings.launchAtLogin   // registering can fail; show what macOS has
                    }
            }

            Section("Permissions") {
                SetupRows(controller: controller)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { controller.refreshPermissions(); launchAtLogin = Settings.launchAtLogin }
    }
}

struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "0"))"
    }

    var body: some View {
        VStack(spacing: 6) {
            AppIconImage(size: 96)
            Text("Lorito").font(.title.bold())
            Text(version).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Repeats exactly what you say, in text. Fast, and all on your Mac.")
                .multilineTextAlignment(.center).padding(.top, 4)
            Form {
                Section {
                    LabeledContent("Speech recognition") {
                        Link("parakeet-tdt-0.6b-v3 by NVIDIA, CC-BY-4.0", destination: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!)
                    }
                    LabeledContent("Runs on") {
                        Link("FluidAudio, Apache-2.0", destination: URL(string: "https://github.com/FluidInference/FluidAudio")!)
                    }
                    LabeledContent("Lorito") {
                        Link("MIT license, source on GitHub", destination: URL(string: "https://github.com/jorisrombouts/Lorito")!)
                    }
                }
                Section {
                    LabeledContent("Log") {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                    }
                } footer: {
                    Text("Timings and errors only. What you say is never written to it, and nothing leaves your Mac.").settingsFooter()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }
}

/// Microphone, Accessibility and the speech model, each with its state and the one action that fixes it.
/// Shared by Onboarding and Settings › Permissions.
struct SetupRows: View {
    let controller: DictationController

    var body: some View {
        SetupRow(symbol: "mic", title: "Microphone", detail: "Hears you while you hold the key.", done: controller.micStatus == .authorized) {
            if controller.micStatus == .notDetermined {
                Button("Allow…") { controller.requestMicrophone() }
            } else {
                Button("Open Settings…") { openPrivacy("Privacy_Microphone") }
            }
        }
        SetupRow(symbol: "accessibility", title: "Accessibility", detail: "Pastes the text at your cursor.", done: controller.axTrusted) {
            Button("Open Settings…") { controller.requestAccessibility() }
        }
        SetupRow(symbol: "waveform", title: "Speech model", detail: modelDetail, done: controller.model == .ready) {
            switch controller.model {
            case .loading(let f, _):
                if f > 0 { ProgressView(value: f).frame(width: 90) } else { ProgressView().controlSize(.small) }
            case .failed: Button("Retry") { controller.loadEngine() }
            case .ready: EmptyView()
            }
        }
    }

    private var modelDetail: String {
        switch controller.model {
        case .loading(let f, let what): f > 0 ? "\(what), \(Int(f * 100))%" : "Downloads once, 461 MB, then works offline."
        case .failed(let why): "Could not load: \(why)"
        case .ready: "Ready, on the Neural Engine."
        }
    }

    private func openPrivacy(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

struct SetupRow<Action: View>: View {
    let symbol: String, title: String, detail: String, done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                    .accessibilityLabel("Done")
            } else {
                action()
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 2)
    }
}

/// The app's own icon: the bundle's icns, or the same drawing when run outside the bundle.
struct AppIconImage: View {
    let size: CGFloat
    var body: some View {
        Group {
            if Bundle.main.bundleURL.pathExtension == "app" {
                Image(nsImage: NSApp.applicationIconImage)
            } else {
                AppIconView().scaleEffect(size / 1024).frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Text {
    func settingsFooter() -> some View { font(.callout).foregroundStyle(.secondary) }
}

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lorito.log")
