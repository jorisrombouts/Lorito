import SwiftUI

struct LoritoApp: App {
    private let controller = DictationController.shared
    @AppStorage(Settings.cleanupEnabledKey) private var cleanupEnabled = true
    @AppStorage(Settings.inputDeviceKey) private var inputDevice = ""

    init() {
        // Start after AppKit has finished launching.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DictationController.shared.start() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text(status)
            if let p = controller.problem {
                Text(p)
                Button("Open System Settings…") { openSettings(for: p) }
            }
            Divider()
            Toggle("Clean Up with Apple Intelligence", isOn: $cleanupEnabled)
                .disabled(controller.cleanupUnavailable != nil)
            if let r = controller.cleanupUnavailable { Text(r) }
            Toggle("Launch at Login", isOn: Binding(get: { Settings.launchAtLogin }, set: { Settings.launchAtLogin = $0 }))
            Picker("Microphone", selection: $inputDevice) {
                Text("Automatic (built-in)").tag("")
                ForEach(AudioRecorder.inputDevices(), id: \.uniqueID) {
                    Text($0.localizedName).tag($0.uniqueID)
                }
            }
            Divider()
            if !controller.transcripts.isEmpty {
                Menu("Recent transcriptions") {
                    ForEach(Array(controller.transcripts.enumerated()), id: \.offset) { _, t in
                        Button(t.count > 50 ? t.prefix(50) + "…" : t) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(t, forType: .string)
                        }
                    }
                }
                Divider()
            }
            Button("Quit Lorito") { exit(0) }
                .keyboardShortcut("q")
        } label: {
            menuIcon
        }
        .onChange(of: controller.state) { _, _ in controller.refreshPermissions(prompt: false) }
    }

    private var status: String {
        switch controller.state {
        case .idle: "Idle — hold or tap Left Option to dictate"
        case .listening: "Recording…"
        case .transcribing, .cleaning: "Working…"
        case .done: "Inserted"
        case .fallback(let s): s
        }
    }

    @ViewBuilder private var menuIcon: some View {
        switch controller.state {
        case .listening: Image(systemName: "waveform.badge.mic")
        case .transcribing, .cleaning: Image(systemName: "waveform").symbolEffect(.variableColor)
        default: Image(nsImage: Self.parrot)
        }
    }

    // The app icon's parrot as a menu bar template: head, neck and hooked beak in one silhouette, the eye cut out.
    private static let parrot: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let s = rect.width
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0.10 * s, y: 0.15 * s, width: 0.66 * s, height: 0.66 * s)).fill()
            let path = NSBezierPath()   // one shape at a time: overlapping subpaths would cancel out
            func quad(_ x: CGFloat, _ y: CGFloat, via cx: CGFloat, _ cy: CGFloat) {   // same curves as make-icon.swift
                let a = path.currentPoint, b = p(x, y), c = p(cx, cy)
                path.curve(to: b, controlPoint1: NSPoint(x: a.x + 2 / 3 * (c.x - a.x), y: a.y + 2 / 3 * (c.y - a.y)),
                           controlPoint2: NSPoint(x: b.x + 2 / 3 * (c.x - b.x), y: b.y + 2 / 3 * (c.y - b.y)))
            }
            path.move(to: p(0.14, 0.60)); quad(0.08, 0.96, via: 0.02, 0.80); path.line(to: p(0.72, 0.96)); quad(0.70, 0.62, via: 0.78, 0.82); path.close(); path.fill()
            path.removeAllPoints()
            path.move(to: p(0.62, 0.30)); quad(0.98, 0.46, via: 0.92, 0.26); quad(0.86, 0.70, via: 1.00, 0.62); quad(0.72, 0.56, via: 0.82, 0.58); quad(0.62, 0.30, via: 0.66, 0.44); path.close(); path.fill()
            path.removeAllPoints()
            path.move(to: p(0.70, 0.58)); quad(0.86, 0.72, via: 0.82, 0.60); quad(0.68, 0.72, via: 0.78, 0.78); path.close(); path.fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSBezierPath(ovalIn: NSRect(x: 0.47 * s, y: 0.37 * s, width: 0.12 * s, height: 0.12 * s)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func openSettings(for problem: String) {
        let pane = problem.hasPrefix("Microphone")
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: pane)!)
    }
}
