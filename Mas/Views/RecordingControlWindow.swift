import AppKit
import SwiftUI

struct RecordingControlView: View {
    @State private var elapsed: TimeInterval = 0
    @State private var dotVisible = true
    let onStop: () -> Void
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let blinkTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(dotVisible ? 1 : 0.3)

            Text(timeString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.75))
        )
        .onReceive(timer) { _ in
            elapsed += 1
        }
        .onReceive(blinkTimer) { _ in
            dotVisible.toggle()
        }
    }

    private var timeString: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

class GeneratingProgressState: ObservableObject {
    @Published var progress: Double = 0
}

struct GeneratingProgressView: View {
    @ObservedObject var state: GeneratingProgressState

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)

            Text(state.progress >= 0.9 ? "GIF書き込み中..." : "GIF生成中 \(Int(state.progress * 100))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(minWidth: 130, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.75))
        )
    }
}

// 録画範囲の枠線を描画するビュー
class RecordingBorderView: NSView {
    private let borderWidth: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)

        // 赤い枠線
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = borderWidth
        path.stroke()
    }
}

@MainActor
class RecordingControlWindowController {
    private var windowController: NSWindowController?
    private var borderWindow: NSWindow?
    private var progressTimer: Timer?

    func show(above region: CGRect, onStop: @escaping () -> Void) {
        let primaryHeight = NSScreen.primaryScreenHeight

        // 録画範囲の枠線ウィンドウ（CG座標→NS座標に変換）
        let borderPadding: CGFloat = 2
        let borderX = region.origin.x - borderPadding
        let borderY = primaryHeight - (region.origin.y + region.height) - borderPadding
        let borderW = region.width + borderPadding * 2
        let borderH = region.height + borderPadding * 2

        let border = NSWindow(
            contentRect: NSRect(x: borderX, y: borderY, width: borderW, height: borderH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        border.level = .floating
        border.backgroundColor = .clear
        border.isOpaque = false
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.sharingType = NSWindow.masSharingType
        border.contentView = RecordingBorderView(frame: NSRect(x: 0, y: 0, width: borderW, height: borderH))
        border.orderFront(nil)
        self.borderWindow = border

        // コントロールパネル
        let controlView = RecordingControlView(onStop: onStop)
        let hostingController = NSHostingController(rootView: controlView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = NSWindow.masSharingType

        let controlWidth: CGFloat = 200
        let controlHeight: CGFloat = 44
        let gap: CGFloat = 12

        let centerX = region.origin.x + region.width / 2 - controlWidth / 2

        // CG座標（左上原点）→ NS座標（左下原点）に変換して上側に配置
        var panelY = primaryHeight - region.origin.y + gap
        // 画面端にclamp
        let targetScreen = NSScreen.screenContaining(cgRect: region)
        let screenFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if panelY + controlHeight > screenFrame.maxY {
            panelY = screenFrame.maxY - controlHeight
        }
        if panelY < screenFrame.minY {
            panelY = screenFrame.minY
        }

        // 左右端もclamp
        var panelX = centerX
        if panelX < screenFrame.minX {
            panelX = screenFrame.minX
        }
        if panelX + controlWidth > screenFrame.maxX {
            panelX = screenFrame.maxX - controlWidth
        }

        panel.setFrame(NSRect(x: panelX, y: panelY, width: controlWidth, height: controlHeight), display: true)

        let controller = NSWindowController(window: panel)
        self.windowController = controller
        controller.showWindow(nil)
    }

    private var progressState: GeneratingProgressState?

    func showGenerating(service: GifRecordingService) {
        // 枠線を消す
        borderWindow?.orderOut(nil)
        borderWindow = nil

        guard let panel = windowController?.window else { return }

        let state = GeneratingProgressState()
        self.progressState = state

        let progressView = GeneratingProgressView(state: state)
        let hostingController = NSHostingController(rootView: progressView)
        panel.contentViewController = hostingController
        panel.isMovableByWindowBackground = false

        // パネルサイズを調整
        let newWidth: CGFloat = 220
        let frame = panel.frame
        let newX = frame.origin.x + (frame.width - newWidth) / 2
        panel.setFrame(NSRect(x: newX, y: frame.origin.y, width: newWidth, height: frame.height), display: true)

        // 定期的にプログレスを更新
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak service, weak state] _ in
            guard let service = service, let state = state else { return }
            Task { @MainActor in
                state.progress = service.generationProgress
            }
        }
    }

    func close() {
        progressTimer?.invalidate()
        progressTimer = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        windowController?.window?.orderOut(nil)
        windowController = nil
    }
}
