import SwiftUI
import AppKit

// MARK: - SwiftUI View

struct ShutterOptionsView: View {
    @ObservedObject var shutterService: ShutterService
    let onStartDelayed: (Int) -> Void
    let onStartInterval: (Int) -> Void
    let onStartChangeDetection: () -> Void
    let onStop: () -> Void

    @State private var selectedDelay: Int = 3
    @State private var selectedInterval: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("シャッターオプション")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider().padding(.horizontal, 8)

            // Delayed Capture
            VStack(alignment: .leading, spacing: 6) {
                Label("遅延キャプチャ", systemImage: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    ForEach([1, 3, 5, 10], id: \.self) { sec in
                        Button("\(sec)秒") {
                            selectedDelay = sec
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: selectedDelay == sec ? .bold : .regular))
                        .foregroundColor(selectedDelay == sec ? .white : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedDelay == sec ? Color.accentColor : Color.gray.opacity(0.2))
                        )
                    }
                }

                if shutterService.activeMode == .delayed {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("\(shutterService.countdown)秒後にキャプチャ")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    if shutterService.activeMode == .delayed {
                        onStop()
                    } else {
                        onStartDelayed(selectedDelay)
                    }
                }) {
                    Text(shutterService.activeMode == .delayed ? "停止" : "開始")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(shutterService.activeMode == .delayed ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(NoHighlightButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Interval Capture
            VStack(alignment: .leading, spacing: 6) {
                Label("インターバル", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    ForEach([1, 3, 5, 10, 30], id: \.self) { sec in
                        Button("\(sec)秒") {
                            selectedInterval = sec
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: selectedInterval == sec ? .bold : .regular))
                        .foregroundColor(selectedInterval == sec ? .white : .primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedInterval == sec ? Color.accentColor : Color.gray.opacity(0.2))
                        )
                    }
                }

                if shutterService.activeMode == .interval {
                    Text("キャプチャ回数: \(shutterService.captureCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    if shutterService.activeMode == .interval {
                        onStop()
                    } else {
                        onStartInterval(selectedInterval)
                    }
                }) {
                    Text(shutterService.activeMode == .interval ? "停止" : "開始")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(shutterService.activeMode == .interval ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(NoHighlightButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Change Detection
            VStack(alignment: .leading, spacing: 6) {
                Label("変化検知", systemImage: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Text("感度")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Slider(value: $shutterService.sensitivity, in: 0.01...0.20, step: 0.01)
                        .controlSize(.small)
                    Text("\(Int(shutterService.sensitivity * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28)
                }

                if shutterService.activeMode == .changeDetection {
                    Text("検知回数: \(shutterService.captureCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    if shutterService.activeMode == .changeDetection {
                        onStop()
                    } else {
                        onStartChangeDetection()
                    }
                }) {
                    Text(shutterService.activeMode == .changeDetection ? "停止" : "開始")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(shutterService.activeMode == .changeDetection ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(NoHighlightButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Window Controller

@MainActor
class ShutterOptionsPanelController {
    let shutterService = ShutterService()
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var cachedSize: CGSize?
    private var captureRegion: CGRect = .zero

    func show(attachedTo parent: NSWindow, screenshot: Screenshot, onRecapture: @escaping (CGRect, NSWindow?) -> Void) {
        parentWindow = parent
        captureRegion = screenshot.captureRegion ?? .zero

        // Set up the capture callback
        shutterService.onCapture = { [weak self] in
            guard let self = self, let parent = self.parentWindow else { return }
            let screenHeight = NSScreen.main?.frame.height ?? 0
            let frame = parent.frame
            let rect = CGRect(
                x: frame.origin.x,
                y: screenHeight - frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
            onRecapture(rect, parent)
        }

        let panelView = ShutterOptionsView(
            shutterService: shutterService,
            onStartDelayed: { [weak self] seconds in
                self?.shutterService.startDelayed(seconds: seconds)
            },
            onStartInterval: { [weak self] seconds in
                self?.shutterService.startInterval(seconds: seconds)
            },
            onStartChangeDetection: { [weak self] in
                guard let self = self else { return }
                self.shutterService.startChangeDetection(
                    regionProvider: { [weak self] in
                        self?.currentCGRegion() ?? .zero
                    }
                )
            },
            onStop: { [weak self] in
                self?.shutterService.stopAll()
            }
        )

        let hosting = NSHostingView(rootView: panelView)
        let fittingSize = hosting.fittingSize
        let width = max(fittingSize.width, 200)
        let height = max(fittingSize.height, 200)
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

        self.window = window

        updatePosition()
        parent.addChildWindow(window, ordered: .above)

        // Fade-in animation
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        // Observe parent window movement and resize
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
        shutterService.stopAll()

        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let panelWindow = window, let parent = parentWindow {
            parent.removeChildWindow(panelWindow)
        }
        window?.orderOut(nil)
        window = nil
        parentWindow = nil
        cachedSize = nil
    }

    func toggle(attachedTo parent: NSWindow, screenshot: Screenshot, onRecapture: @escaping (CGRect, NSWindow?) -> Void) {
        if window != nil {
            close()
        } else {
            show(attachedTo: parent, screenshot: screenshot, onRecapture: onRecapture)
        }
    }

    /// parentWindow の現在位置からCG座標系のリージョンを返す
    func currentCGRegion() -> CGRect {
        guard let parent = parentWindow else { return captureRegion }
        let frame = parent.frame
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private func updatePosition() {
        guard let parent = parentWindow, let panel = window else { return }

        let parentFrame = parent.frame
        let panelSize = cachedSize ?? CGSize(width: 200, height: 300)

        // Place to the right of the parent window
        var panelX = parentFrame.maxX + 4
        var panelY = parentFrame.maxY - panelSize.height

        if let screen = parent.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            // If no room on the right, place on the left
            if panelX + panelSize.width > screenFrame.maxX {
                panelX = parentFrame.minX - panelSize.width - 4
            }

            // Clamp to screen bounds
            if panelX < screenFrame.minX {
                panelX = screenFrame.minX
            }
            if panelY < screenFrame.minY {
                panelY = screenFrame.minY
            }
            if panelY + panelSize.height > screenFrame.maxY {
                panelY = screenFrame.maxY - panelSize.height
            }
        }

        panel.setFrame(
            NSRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height),
            display: false
        )
    }
}
