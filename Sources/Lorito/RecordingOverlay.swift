import AppKit
import SwiftUI

/// Floating, non-activating HUD pill at the bottom-centre of the screen under the mouse.
@MainActor
final class RecordingOverlay {
    private let panel: NSPanel

    init(controller: DictationController) {
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.ignoresMouseEvents = false   // the hands-free ✕ is clickable; the panel still never activates
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the capsule draws its own shadow; a window shadow lags behind the animation
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(controller: controller))
    }

    func show() {
        let size = OverlayView.canvas
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 4, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()   // never makeKey: focus must stay in the target app
    }

    func hide() { panel.orderOut(nil) }
}

struct OverlayView: View {
    /// Transparent window size; the pill sizes itself to its content and animates inside it.
    static let canvas = NSSize(width: 360, height: 80)

    let controller: DictationController

    /// The app icon's parrot in its own colours; while listening the level bars come out of its beak.
    private static let parrot: NSImage = {
        let orange = NSColor.systemOrange
        let image = LoritoApp.parrot(size: 30, bars: orange, beak: orange.blended(withFraction: 0.45, of: .black)!)
        image.isTemplate = false
        return image
    }()

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(nsImage: Self.parrot)
                if controller.state == .listening {
                    LevelBars(level: controller.level).offset(y: 1).transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            label
            if controller.handsFree {
                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.primary).onTapGesture { controller.cancel() }
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassEffect()
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .animation(.easeOut(duration: 0.08), value: controller.level)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: controller.state)
    }

    private var label: some View {
        let text = Self.text(for: controller.state)
        return Text(text)
            .font(.body.weight(.medium))
            .fixedSize()
            .id(text)   // new text fades in while the capsule springs to its new width
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    /// Pill and menu wording for a state.
    static func text(for state: DictationController.State) -> String {
        switch state {
        case .idle: ""
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
        case .done: "Inserted"
        case .fallback(let s): s
        }
    }
}

struct LevelBars: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                // `level` is already relative to the recent peak; per-bar weights so the bars differ.
                let weight = [0.6, 0.9, 1.0, 1.0, 0.8, 0.5][i]
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 3, height: 4 + CGFloat(min(1, Double(level)) * weight) * 14)
            }
        }
        .frame(height: 18)
    }
}
