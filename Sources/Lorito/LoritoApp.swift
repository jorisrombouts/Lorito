import SwiftUI

struct LoritoApp: App {
    private let controller = DictationController.shared

    init() {
        // Start after AppKit has finished launching.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DictationController.shared.start() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            menuIcon
        }
        SwiftUI.Settings {
            SettingsView()
        }
    }

    @ViewBuilder private var menuIcon: some View {
        switch controller.state {
        case .listening: Image(nsImage: Self.parrotListening)
        case .transcribing, .cleaning: Image(nsImage: Self.parrotWorking)
        default: Image(nsImage: Self.parrot)
        }
    }

    // The parrot of the app icon, drawn once for both: bars on the head-and-neck silhouette, solid hooked beak, eye.
    // The paths are sampled at 680 pt whatever the output size, because SwiftUI `Path.contains` flattens curves with an
    // absolute tolerance and would give other bar tops at 18 pt. Eleven columns, ten show, the last is under the beak.
    // Menu bar: black template, eye cut out; listening adds a dot in the free corner, working dims the whole glyph.
    private static let parrot = parrot()
    private static let parrotListening = parrot(dot: true)
    private static let parrotWorking = parrot(alpha: 0.45)
    static func parrot(size: CGFloat = 18, bars: NSColor = .black, beak beakColor: NSColor = .black, eye: NSColor? = nil,
                       dot: Bool = false, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
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
            bars.setFill()
            let pitch = 0.72 * s / 11, w = pitch * 0.58
            for i in 0..<11 {   // one rounded bar per column, its ends on the silhouette
                let x = 0.06 * s + pitch * (CGFloat(i) + 0.5)
                var top: CGFloat? = nil, bottom: CGFloat = 0
                var y: CGFloat = 0
                while y <= s { if body.contains(CGPoint(x: x, y: y)) { if top == nil { top = y }; bottom = y }; y += 2 }
                guard let t = top else { continue }
                NSBezierPath(roundedRect: NSRect(x: (x - w / 2) * k, y: t * k, width: w * k, height: max(bottom - t, w) * k), xRadius: w * k / 2, yRadius: w * k / 2).fill()
            }
            beakColor.setFill()
            NSBezierPath(cgPath: beak.applying(CGAffineTransform(scaleX: k, y: k)).cgPath).fill()
            if let eye { eye.setFill() } else { ctx.setBlendMode(.clear) }
            NSBezierPath(ovalIn: NSRect(x: 0.47 * s * k, y: 0.37 * s * k, width: 0.12 * s * k, height: 0.12 * s * k)).fill()
            ctx.setBlendMode(.normal)
            if dot { bars.setFill(); NSBezierPath(ovalIn: NSRect(x: 0.80 * s * k, y: 0.80 * s * k, width: 0.20 * s * k, height: 0.20 * s * k)).fill() }
            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = eye == nil
        return image
    }

}

/// The app icon: Apple's Tahoe recipe in system orange, light tint down to the colour, white glyph, a darker shade for depth.
/// `Lorito --icon out.png` renders it at 1024 px; build-app.sh turns that into the bundle's icns.
/// Status, what needs fixing, recent dictations, Settings and Quit. Everything adjustable lives in Settings.
struct MenuContent: View {
    let controller: DictationController
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Settings.hotkeyKey) private var hotkey = Hotkey.leftOption

    var body: some View {
        Text(status)
        if let p = controller.problem {
            Text(p)
            Button("Set Up Lorito…") { controller.showOnboarding() }
        }
        Divider()
        if !controller.transcripts.isEmpty {
            Section("Recent — click to copy") {
                ForEach(Array(controller.transcripts.enumerated()), id: \.offset) { _, t in
                    Button(t.count > 60 ? t.prefix(60) + "…" : t) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(t, forType: .string)
                    }
                }
            }
            Divider()
        }
        Button("Settings…") {
            NSApp.activate()   // an LSUIElement app's windows open behind the frontmost app otherwise
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Lorito") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onChange(of: controller.state) { _, _ in controller.refreshPermissions() }
    }

    private var status: String {
        controller.state == .idle ? "Hold or tap \(hotkey.name) to dictate" : OverlayView.text(for: controller.state)
    }
}

struct AppIconView: View {
    static func mix(_ c: NSColor, _ with: NSColor, _ f: CGFloat) -> Color { Color(nsColor: c.blended(withFraction: f, of: with)!) }
    var body: some View {
        let orange = NSColor.systemOrange
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)   // Apple macOS icon grid: 824 pt square, 184 pt corners
                .fill(LinearGradient(colors: [Self.mix(orange, .white, 0.30), Self.mix(orange, .black, 0.10)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 184, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center)))
                .overlay(RoundedRectangle(cornerRadius: 184, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 4))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            Image(nsImage: LoritoApp.parrot(size: 680, bars: .white, beak: orange.blended(withFraction: 0.45, of: .black)!,
                                            eye: orange.blended(withFraction: 0.05, of: .black)!))
                .offset(x: -30, y: 90)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
        }
        .padding(100)
        .frame(width: 1024, height: 1024)
    }
}
