import SwiftUI
import AppKit
import AVFoundation

struct VideoPlayerToolbarView: View {
    @ObservedObject var playerState: VideoPlayerState
    var onTrimComplete: ((URL) -> Void)?
    var onGifExportComplete: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            if playerState.isTrimming {
                trimToolbar
            } else {
                mainToolbar
            }
        }
    }

    private var mainToolbar: some View {
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

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // 音量コントロール
            Button(action: { playerState.isMuted.toggle() }) {
                Image(systemName: playerState.isMuted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Slider(value: $playerState.volume, in: 0...1)
                .frame(width: 50)
                .tint(.white)

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // トリムボタン
            Button(action: { playerState.enterTrimMode() }) {
                Image(systemName: "scissors")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .help("トリム")

            // GIF保存ボタン
            Button(action: { exportAsGif() }) {
                if playerState.isExportingGif {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                } else {
                    Text("GIF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .disabled(playerState.isExportingGif)
            .help("GIFとして保存")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
        )
    }

    private var trimToolbar: some View {
        VStack(spacing: 4) {
            // トリム範囲バー
            TrimRangeBar(
                duration: playerState.duration,
                trimStart: $playerState.trimStart,
                trimEnd: $playerState.trimEnd,
                onSeek: { playerState.seek(to: $0) }
            )
            .frame(height: 24)

            HStack(spacing: 8) {
                // 開始点設定
                Button(action: { playerState.setTrimStart() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "bracket.square.left.fill")
                            .font(.system(size: 10))
                        Text(formatTime(playerState.trimStart))
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .help("現在位置を開始点に設定")

                // 再生コントロール
                Button(action: { playerState.prevFrame() }) {
                    Image(systemName: "backward.frame.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                Button(action: { playerState.togglePlayPause() }) {
                    Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                Button(action: { playerState.nextFrame() }) {
                    Image(systemName: "forward.frame.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                // 終了点設定
                Button(action: { playerState.setTrimEnd() }) {
                    HStack(spacing: 3) {
                        Text(formatTime(playerState.trimEnd))
                            .font(.system(size: 10, design: .monospaced))
                        Image(systemName: "bracket.square.right.fill")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .help("現在位置を終了点に設定")

                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.3))

                // トリム時間表示
                Text(formatTime(playerState.trimDuration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.3))

                // キャンセル
                Button(action: { playerState.exitTrimMode() }) {
                    Text("キャンセル")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)

                // 書き出し
                Button(action: { exportTrimmed() }) {
                    HStack(spacing: 3) {
                        if playerState.isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .colorScheme(.dark)
                        } else {
                            Image(systemName: "scissors")
                                .font(.system(size: 10))
                        }
                        Text("切り出し")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .disabled(playerState.isExporting || playerState.isExportingGif)

                // GIF保存（トリム範囲）
                Button(action: { exportAsGif() }) {
                    HStack(spacing: 3) {
                        if playerState.isExportingGif {
                            ProgressView()
                                .controlSize(.small)
                                .colorScheme(.dark)
                        } else {
                            Text("GIF")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        if playerState.isExportingGif && playerState.gifExportProgress > 0 {
                            Text("\(Int(playerState.gifExportProgress * 100))%")
                                .font(.system(size: 9, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .disabled(playerState.isExporting || playerState.isExportingGif)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
        )
    }

    private func exportTrimmed() {
        Task {
            if let outputURL = await playerState.exportTrimmed() {
                playerState.exitTrimMode()
                onTrimComplete?(outputURL)
            }
        }
    }

    private func exportAsGif() {
        Task {
            if let outputURL = await playerState.exportAsGif() {
                if playerState.isTrimming {
                    playerState.exitTrimMode()
                }
                onGifExportComplete?(outputURL)
            }
        }
    }

    private var volumeIcon: String {
        if playerState.volume == 0 { return "speaker.slash.fill" }
        if playerState.volume < 0.33 { return "speaker.wave.1.fill" }
        if playerState.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
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
        let ms = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}

// トリム範囲を視覚的に表示・操作するバー
struct TrimRangeBar: View {
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = duration > 0 ? CGFloat(trimStart / duration) * width : 0
            let endX = duration > 0 ? CGFloat(trimEnd / duration) * width : width

            ZStack(alignment: .leading) {
                // 背景（範囲外をグレーに）
                Rectangle()
                    .fill(Color.white.opacity(0.15))

                // 選択範囲
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: max(endX - startX, 1))
                    .offset(x: startX)

                // 開始ハンドル
                trimHandle(color: .blue)
                    .offset(x: startX - 6)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newStart = Double(value.location.x / width) * duration
                                trimStart = max(0, min(newStart, trimEnd - (1.0 / max(playerFps, 1))))
                                onSeek(trimStart)
                            }
                    )

                // 終了ハンドル
                trimHandle(color: .blue)
                    .offset(x: endX - 6)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newEnd = Double(value.location.x / width) * duration
                                trimEnd = min(duration, max(newEnd, trimStart + (1.0 / max(playerFps, 1))))
                                onSeek(trimEnd)
                            }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
    }

    private var playerFps: Double { 20 }

    private func trimHandle(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 12, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
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

    func show(attachedTo parent: NSWindow, playerState: VideoPlayerState, onTrimComplete: ((URL) -> Void)? = nil, onGifExportComplete: ((URL) -> Void)? = nil) {
        parentWindow = parent

        let toolbarView = VideoPlayerToolbarView(playerState: playerState, onTrimComplete: onTrimComplete, onGifExportComplete: onGifExportComplete)
        let hosting = NSHostingView(rootView: toolbarView)

        let fittingSize = hosting.fittingSize
        let width = max(fittingSize.width, 500)
        let height: CGFloat = 80
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
        let toolbarSize = cachedSize ?? CGSize(width: 500, height: 80)

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
