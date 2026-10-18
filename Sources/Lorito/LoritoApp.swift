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
        case .listening: Image(nsImage: Self.parrotListening)
        case .transcribing, .cleaning: Image(nsImage: Self.parrotWorking)
        default: Image(nsImage: Self.parrot)
        }
    }

    // The app icon as a menu bar template: the paths and bar sampling of make-icon.swift, run at the icon's own 680 pt
    // (SwiftUI `Path.contains` flattens curves with an absolute tolerance, so it is scale-dependent) and scaled down, so
    // the bars match the shipped icns exactly (ten show, the eleventh is under the beak). Eye cut out.
    // Listening adds a recording dot in the free bottom-right corner; working draws the parrot at half strength.
    private static let parrot = parrot()
    private static let parrotListening = parrot(dot: true)
    private static let parrotWorking = parrot(alpha: 0.45)
    private static func parrot(dot: Bool = false, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let s: CGFloat = 680, k = rect.width / s
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var body = Path()
            body.addEllipse(in: CGRect(x: 0.10 * s, y: 0.15 * s, width: 0.66 * s, height: 0.66 * s))
            body.move(to: p(0.14, 0.60)); body.addQuadCurve(to: p(0.08, 0.96), control: p(0.02, 0.80)); body.addLine(to: p(0.72, 0.96)); body.addQuadCurve(to: p(0.70, 0.62), control: p(0.78, 0.82)); body.closeSubpath()
            var beak = Path()
            beak.move(to: p(0.62, 0.30)); beak.addQuadCurve(to: p(0.98, 0.46), control: p(0.92, 0.26)); beak.addQuadCurve(to: p(0.86, 0.70), control: p(1.00, 0.62)); beak.addQuadCurve(to: p(0.72, 0.56), control: p(0.82, 0.58)); beak.addQuadCurve(to: p(0.62, 0.30), control: p(0.66, 0.44)); beak.closeSubpath()
            beak.move(to: p(0.70, 0.58)); beak.addQuadCurve(to: p(0.86, 0.72), control: p(0.82, 0.60)); beak.addQuadCurve(to: p(0.68, 0.72), control: p(0.78, 0.78)); beak.closeSubpath()
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setAlpha(alpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil)   // dim the glyph as one layer
            NSColor.black.setFill()
            let bars = 11, pitch = 0.72 * s / 11, w = pitch * 0.58
            for i in 0..<bars {   // one rounded bar per column, its ends on the silhouette
                let x = 0.06 * s + pitch * (CGFloat(i) + 0.5)
                var top: CGFloat? = nil, bottom: CGFloat = 0
                var y: CGFloat = 0
                while y <= s { if body.contains(CGPoint(x: x, y: y)) { if top == nil { top = y }; bottom = y }; y += 2 }
                guard let t = top else { continue }
                NSBezierPath(roundedRect: NSRect(x: (x - w / 2) * k, y: t * k, width: w * k, height: max(bottom - t, w) * k), xRadius: w * k / 2, yRadius: w * k / 2).fill()
            }
            NSBezierPath(cgPath: beak.applying(CGAffineTransform(scaleX: k, y: k)).cgPath).fill()
            ctx.setBlendMode(.clear)
            NSBezierPath(ovalIn: NSRect(x: 0.47 * s * k, y: 0.37 * s * k, width: 0.12 * s * k, height: 0.12 * s * k)).fill()
            ctx.setBlendMode(.normal)
            if dot { NSBezierPath(ovalIn: NSRect(x: 0.80 * s * k, y: 0.80 * s * k, width: 0.20 * s * k, height: 0.20 * s * k)).fill() }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func openSettings(for problem: String) {
        let pane = problem.hasPrefix("Microphone")
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: pane)!)
    }
}
