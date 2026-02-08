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

    func show(above region: CGRect, onStop: @escaping () -> Void) {
        let screenHeight = NSScreen.main?.frame.height ?? 0

        // 録画範囲の枠線ウィンドウ
        let borderPadding: CGFloat = 2
        let borderX = region.origin.x - borderPadding
        let borderY = screenHeight - (region.origin.y + region.height) - borderPadding
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
        border.contentView = RecordingBorderView(frame: NSRect(x: 0, y: 0, width: borderW, height: borderH))
        border.orderFront(nil)
        self.borderWindow = border

        // コントロールパネル
        let controlView = RecordingControlView(onStop: onStop)
        let hostingController = NSHostingController(rootView: controlView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 44),
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

        let controlWidth: CGFloat = 180
        let controlHeight: CGFloat = 44
        let gap: CGFloat = 12

        let centerX = region.origin.x + region.width / 2 - controlWidth / 2

        // 左上原点 → 左下原点に変換して上側に配置
        var panelY = screenHeight - region.origin.y + gap
        // 画面上部に余裕がなければ下側に配置
        if panelY + controlHeight > screenHeight {
            panelY = screenHeight - (region.origin.y + region.height) - controlHeight - gap
        }

        panel.setFrame(NSRect(x: centerX, y: panelY, width: controlWidth, height: controlHeight), display: true)

        let controller = NSWindowController(window: panel)
        self.windowController = controller
        controller.showWindow(nil)
    }

    func close() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
        windowController?.window?.orderOut(nil)
        windowController = nil
    }
}
