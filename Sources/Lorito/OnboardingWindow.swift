import AppKit
import SwiftUI

/// First launch, and whenever a permission or the model is missing: the three things Lorito needs, live.
/// An AppKit window so the controller can open it at launch; the app is `LSUIElement`, so it activates itself first.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let controller: DictationController
    private var window: NSWindow?
    private var poll: Timer?

    init(controller: DictationController) { self.controller = controller }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Welcome to Lorito"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(controller: controller) { [weak self] in self?.finish() })
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            window = w
        }
        // Permissions change in System Settings, which tells nobody; look once a second while this is open.
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { self.controller.refreshPermissions() } }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Settings.onboardedKey)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate(); poll = nil
        if controller.ready { UserDefaults.standard.set(true, forKey: Settings.onboardedKey) }
    }
}

struct OnboardingView: View {
    let controller: DictationController
    let done: () -> Void
    @AppStorage(Settings.hotkeyKey) private var hotkey = Hotkey.leftOption

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                AppIconImage(size: 96)
                Text("Welcome to Lorito").font(.title.bold())
                Text("Talk, and the text appears at your cursor. Everything stays on this Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)
            .padding(.horizontal, 32)

            Form {
                Section { SetupRows(controller: controller) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(controller.ready ? "Try it: hold \(hotkey.name), say something, let go." : "Lorito works once all three are ticked.")
                    .foregroundStyle(controller.ready ? .primary : .secondary)
                    .animation(.default, value: controller.ready)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!controller.ready)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 480)
        .tint(.orange)
    }
}
