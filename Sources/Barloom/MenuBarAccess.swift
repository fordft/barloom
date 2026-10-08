import AppKit
import ApplicationServices
import BarloomMenuBarNative
import Combine
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class MenuBarAccess: ObservableObject {
    @Published private(set) var canCapture = false
    @Published private(set) var canControl = false
    private var observations: Set<AnyCancellable> = []

    init() {
        refresh()
        NSApplication.shared.publisher(for: \.isActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &observations)
    }

    func refresh() {
        let capture = CGPreflightScreenCaptureAccess()
        let control = AXIsProcessTrusted()
        if canCapture != capture { canCapture = capture }
        if canControl != control { canControl = control }
    }

    func requestCapture() {
        // The system prompt is invoked only by the user's Allow button.
        SCShareableContent.getWithCompletionHandler { _, _ in }
        openSettings("Privacy_ScreenCapture")
    }

    func requestControl() {
        _ = BRLRequestAccessibilityTrust()
        openSettings("Privacy_Accessibility")
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
