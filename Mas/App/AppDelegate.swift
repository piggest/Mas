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
        setupDistributedNotifications()
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
        popover?.contentSize = NSSize(width: 250, height: 500)
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

    // MARK: - CLI連携（DistributedNotificationCenter）

    private func setupDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(handleDistributedCaptureFullScreen),
            name: NSNotification.Name("com.example.Mas.capture.fullscreen"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedCaptureRegion),
            name: NSNotification.Name("com.example.Mas.capture.region"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedCaptureFrame),
            name: NSNotification.Name("com.example.Mas.capture.frame"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedShowHistory),
            name: NSNotification.Name("com.example.Mas.show.history"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedOpenFile(_:)),
            name: NSNotification.Name("com.example.Mas.open.file"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedShowMenu),
            name: NSNotification.Name("com.example.Mas.show.menu"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedShowLibrary),
            name: NSNotification.Name("com.example.Mas.show.library"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedShowSettings),
            name: NSNotification.Name("com.example.Mas.show.settings"), object: nil)
        dnc.addObserver(self, selector: #selector(handleDistributedGifRecording),
            name: NSNotification.Name("com.example.Mas.capture.gif"), object: nil)
    }

    @objc private func handleDistributedCaptureFullScreen() {
        NotificationCenter.default.post(name: .captureFullScreen, object: nil)
    }

    @objc private func handleDistributedCaptureRegion() {
        NotificationCenter.default.post(name: .captureRegion, object: nil)
    }

    @objc private func handleDistributedCaptureFrame() {
        NotificationCenter.default.post(name: .showCaptureFrame, object: nil)
    }

    @objc private func handleDistributedShowHistory() {
        captureViewModel.showHistoryWindow()
    }

    @objc private func handleDistributedShowMenu() {
        guard let button = statusItem?.button else { return }
        if let popover = popover, !popover.isShown {
            popover.behavior = .applicationDefined  // 自動で閉じないようにする
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func handleDistributedShowLibrary() {
        captureViewModel.showHistoryWindow()
    }

    @objc private func handleDistributedShowSettings() {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "設定"
        settingsWindow.contentViewController = NSHostingController(rootView: SettingsWindow())
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleDistributedGifRecording() {
        NotificationCenter.default.post(name: .startGifRecording, object: nil)
    }

    @objc private func handleDistributedOpenFile(_ notification: Notification) {
        guard let filePath = notification.object as? String else { return }
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath),
              let image = NSImage(contentsOf: url) else { return }
        captureViewModel.openImageFromCLI(image: image, filePath: filePath)
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
            keyCode: HotkeyConfig.frameKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .showCaptureFrame, object: nil)
        }

        hotkeyManager.register(
            keyCode: HotkeyConfig.gifRecordingKeyCode,
            modifiers: HotkeyConfig.modifiers
        ) {
            NotificationCenter.default.post(name: .startGifRecording, object: nil)
        }
    }
}

extension Notification.Name {
    static let captureFullScreen = Notification.Name("captureFullScreen")
    static let captureRegion = Notification.Name("captureRegion")
    static let showCaptureFrame = Notification.Name("showCaptureFrame")
    static let editorWindowClosed = Notification.Name("editorWindowClosed")
    static let windowPinChanged = Notification.Name("windowPinChanged")
    static let showHistory = Notification.Name("showHistory")
    static let startGifRecording = Notification.Name("startGifRecording")
}
