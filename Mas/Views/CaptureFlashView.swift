import AppKit

@MainActor
class CaptureFlashView {
    private var flashWindow: NSWindow?

    func showFlash(in rect: CGRect) {
        // 画面座標系（左上原点）から左下原点に変換
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let windowRect = NSRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        // 既存のフラッシュウィンドウをクリア
        flashWindow?.orderOut(nil)
        flashWindow = nil

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // 最前面に表示
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.backgroundColor = NSColor.white
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0.8
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        flashWindow = window
        window.orderFrontRegardless()

        // アニメーションで白を消していく
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.flashWindow?.orderOut(nil)
            self?.flashWindow = nil
        })
    }
}
