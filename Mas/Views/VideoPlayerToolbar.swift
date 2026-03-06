import SwiftUI
import AppKit
import AVFoundation

struct VideoPlayerToolbarView: View {
    @ObservedObject var playerState: VideoPlayerState

    var body: some View {
        HStack(spacing: 8) {
            // 前フレーム
            Button(action: { playerState.prevFrame() }) {
                Image(systemName: "backward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // 5秒戻し
            Button(action: { playerState.skipBackward(5) }) {
                Image(systemName: "gobackward.5")
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

            // 5秒送り
            Button(action: { playerState.skipForward(5) }) {
                Image(systemName: "goforward.5")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            // 次フレーム
            Button(action: { playerState.nextFrame() }) {
                Image(systemName: "forward.frame.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // 時間 + フレーム表示
            VStack(spacing: 0) {
                Text(formatTime(playerState.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Text("\(playerState.currentFrame)/\(playerState.totalFrames)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(minWidth: 42)

            // シークバー
            ScrubSlider(
                value: Binding(
                    get: { playerState.currentTime },
                    set: { playerState.seek(to: $0) }
                ),
                range: 0...max(playerState.duration, 0.1),
                onScrubStart: { playerState.beginScrubbing() },
                onScrubEnd: { playerState.endScrubbing() }
            )
            .frame(minWidth: 100, maxHeight: 20)

            VStack(spacing: 0) {
                Text(formatTime(playerState.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Text("\(Int(playerState.fps))fps")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(minWidth: 42)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // 速度切替
            Menu {
                Button("0.5x") { playerState.setSpeed(0.5) }
                Button("1x") { playerState.setSpeed(1.0) }
                Button("2x") { playerState.setSpeed(2.0) }
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

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// AppKitレベルでmouseDown/mouseUpを検知するスライダー
struct ScrubSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onScrubStart: () -> Void
    let onScrubEnd: () -> Void

    func makeNSView(context: Context) -> ScrubNSSlider {
        let slider = ScrubNSSlider()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.onMouseDown = onScrubStart
        slider.onMouseUp = onScrubEnd
        return slider
    }

    func updateNSView(_ nsView: ScrubNSSlider, context: Context) {
        if !nsView.isScrubbing {
            nsView.doubleValue = value
        }
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        nsView.onMouseDown = onScrubStart
        nsView.onMouseUp = onScrubEnd
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

class ScrubNSSlider: NSSlider {
    var onMouseDown: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var isScrubbing = false

    override func mouseDown(with event: NSEvent) {
        isScrubbing = true
        onMouseDown?()
        super.mouseDown(with: event)
        // super.mouseDown returns when mouse is released
        isScrubbing = false
        onMouseUp?()
    }
}

@MainActor
class VideoPlayerToolbarController {
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var cachedSize: CGSize?

    func show(attachedTo parent: NSWindow, playerState: VideoPlayerState) {
        parentWindow = parent

        let toolbarView = VideoPlayerToolbarView(playerState: playerState)
        let hosting = NSHostingView(rootView: toolbarView)

        let fittingSize = hosting.fittingSize
        let width = max(fittingSize.width, 460)
        let height = max(fittingSize.height, 48)
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
        window.sharingType = NSWindow.masSharingType

        self.window = window

        updatePosition()
        parent.addChildWindow(window, ordered: .above)

        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

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
        let toolbarSize = cachedSize ?? CGSize(width: 460, height: 48)

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
