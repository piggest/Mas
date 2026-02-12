import SwiftUI
import AppKit

struct GifPlayerToolbarView: View {
    @ObservedObject var playerState: GifPlayerState

    var body: some View {
        HStack(spacing: 10) {
            // 前のフレーム
            Button(action: { playerState.prevFrame() }) {
                Image(systemName: "backward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // 再生/一時停止
            Button(action: { playerState.togglePlayPause() }) {
                Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // 次のフレーム
            Button(action: { playerState.nextFrame() }) {
                Image(systemName: "forward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // フレームスライダー
            Slider(
                value: Binding(
                    get: { Double(playerState.currentFrameIndex) },
                    set: { playerState.seekTo(frame: Int($0)) }
                ),
                in: 0...Double(max(playerState.frameCount - 1, 1)),
                step: 1
            )
            .frame(minWidth: 100)
            .controlSize(.small)

            // フレーム番号
            Text("\(playerState.currentFrameIndex + 1)/\(playerState.frameCount)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 50)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // 速度切替
            Menu {
                Button("0.5x") { playerState.speed = 0.5 }
                Button("1x") { playerState.speed = 1.0 }
                Button("2x") { playerState.speed = 2.0 }
            } label: {
                Text(speedLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
        )
    }

    private var speedLabel: String {
        if playerState.speed == 0.5 { return "0.5x" }
        if playerState.speed == 1.0 { return "1x" }
        if playerState.speed == 2.0 { return "2x" }
        return "\(playerState.speed)x"
    }
}

@MainActor
class GifPlayerToolbarController {
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var cachedSize: CGSize?

    func show(attachedTo parent: NSWindow, playerState: GifPlayerState) {
        parentWindow = parent

        let toolbarView = GifPlayerToolbarView(playerState: playerState)
        let hosting = NSHostingView(rootView: toolbarView)

        let fittingSize = hosting.fittingSize
        let width = max(fittingSize.width, 360)
        let height = max(fittingSize.height, 44)
        cachedSize = CGSize(width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.sharingType = .none

        self.window = window

        updatePosition()
        parent.addChildWindow(window, ordered: .above)

        // 出現アニメーション
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        // 親ウィンドウの移動・リサイズを監視
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    func close() {
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let toolbarWindow = window, let parent = parentWindow {
            parent.removeChildWindow(toolbarWindow)
        }
        window?.orderOut(nil)
        window = nil
        parentWindow = nil
        cachedSize = nil
    }

    private func updatePosition() {
        guard let parent = parentWindow, let toolbar = window else { return }

        let parentFrame = parent.frame
        let toolbarSize = cachedSize ?? CGSize(width: 360, height: 44)

        // 親ウィンドウの下部中央に配置
        var toolbarX = parentFrame.midX - toolbarSize.width / 2
        var toolbarY = parentFrame.origin.y - toolbarSize.height + 4

        if let screen = parent.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            if toolbarX < screenFrame.minX {
                toolbarX = screenFrame.minX
            }
            if toolbarX + toolbarSize.width > screenFrame.maxX {
                toolbarX = screenFrame.maxX - toolbarSize.width
            }
            // 下端チェック（画面下端に粘りつく）
            if toolbarY < screenFrame.minY {
                toolbarY = screenFrame.minY
            }
            if toolbarY + toolbarSize.height > screenFrame.maxY {
                toolbarY = screenFrame.maxY - toolbarSize.height
            }
        }

        toolbar.setFrame(
            NSRect(x: toolbarX, y: toolbarY, width: toolbarSize.width, height: toolbarSize.height),
            display: false
        )
    }
}
