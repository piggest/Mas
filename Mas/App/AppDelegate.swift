import AppKit
import CoreGraphics
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager.shared
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var lastClickTime: Date?
    private let doubleClickInterval: TimeInterval = 0.3
    private let captureViewModel = CaptureViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotkeyHandlers()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // アプリアイコンを使用
            if let image = NSApp.applicationIconImage {
                let size = NSSize(width: 18, height: 18)
                let resizedImage = NSImage(size: size)
                resizedImage.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: size),
                          from: NSRect(origin: .zero, size: image.size),
                          operation: .copy,
                          fraction: 1.0)
                resizedImage.unlockFocus()
                resizedImage.isTemplate = false
                button.image = resizedImage
            } else {
                // フォールバック
                button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Mas")
            }
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // ポップオーバーの設定
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 250, height: 400)
        popover?.behavior = .transient
        let menuBarView = MenuBarView().environmentObject(captureViewModel)
        popover?.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // 右クリックの場合はメニューを表示
        if event.type == .rightMouseUp {
            showPopover(sender)
            return
        }

        // ダブルクリック判定
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < doubleClickInterval {
            // ダブルクリック - 範囲キャプチャ
            lastClickTime = nil
            popover?.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .captureRegion, object: nil)
            }
        } else {
            // シングルクリック - ポップオーバー表示
            lastClickTime = now
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
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

        hotkeyManager.register(
            keyCode: HotkeyConfig.frameKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .showCaptureFrame, object: nil)
        }
    }
}

extension Notification.Name {
    static let captureFullScreen = Notification.Name("captureFullScreen")
    static let captureRegion = Notification.Name("captureRegion")
    static let showCaptureFrame = Notification.Name("showCaptureFrame")
    static let captureWindow = Notification.Name("captureWindow")
    static let editorWindowClosed = Notification.Name("editorWindowClosed")
}
