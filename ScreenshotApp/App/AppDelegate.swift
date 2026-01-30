import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 許可チェックは行わない（screencaptureコマンドは許可不要）
        setupHotkeyHandlers()
    }

    private func setupHotkeyHandlers() {
        hotkeyManager.register(
            keyCode: HotkeyConfig.fullScreenKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .captureFullScreen, object: nil)
        }

        hotkeyManager.register(
            keyCode: HotkeyConfig.regionKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .captureRegion, object: nil)
        }

        hotkeyManager.register(
            keyCode: HotkeyConfig.windowKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .captureWindow, object: nil)
        }
    }
}

extension Notification.Name {
    static let captureFullScreen = Notification.Name("captureFullScreen")
    static let captureRegion = Notification.Name("captureRegion")
    static let captureWindow = Notification.Name("captureWindow")
}
