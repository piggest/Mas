import SwiftUI
import AppKit

// MARK: - VisualEffectBlur Helper

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - SwiftUI View

struct ShutterOptionsView: View {
    @ObservedObject var shutterService: ShutterService
    let onStartDelayed: (Int) -> Void
    let onStartInterval: (Double, Int) -> Void
    let onStartChangeDetection: () -> Void
    let onStop: () -> Void

    @State private var selectedDelay: Double = 3
    @State private var selectedInterval: Double = 5
    @State private var maxCaptureCount: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("シャッターオプション")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 12)

            // Delayed Capture
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("遅延キャプチャ", icon: "timer", isActive: shutterService.activeMode == .delayed)

                    HStack(spacing: 6) {
                        Slider(value: $selectedDelay, in: 1...30, step: 1)
                            .controlSize(.small)
                            .tint(.cyan)
                        Text("\(Int(selectedDelay))秒")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 30, alignment: .trailing)
                    }

                    if shutterService.activeMode == .delayed {
                        progressBadge {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                                Text("\(shutterService.countdown)秒後にキャプチャ")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }

                    actionButton(
                        isActive: shutterService.activeMode == .delayed,
                        startAction: { onStartDelayed(Int(selectedDelay)) },
                        stopAction: onStop
                    )
                }
            }

            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 12)

            // Interval Capture
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("インターバル", icon: "arrow.triangle.2.circlepath", isActive: shutterService.activeMode == .interval)

                    HStack(spacing: 6) {
                        Slider(value: $selectedInterval, in: 0.5...60, step: 0.5)
                            .controlSize(.small)
                            .tint(.cyan)
                        Text(intervalLabel(selectedInterval))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 38, alignment: .trailing)
                    }

                    // 回数制限
                    HStack(spacing: 6) {
                        Text("回数")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 24, alignment: .leading)
                        Slider(value: $maxCaptureCount, in: 0...1000, step: 1)
                            .controlSize(.small)
                            .tint(.cyan)
                        TextField("", value: Binding(
                            get: { Int(self.maxCaptureCount) },
                            set: { self.maxCaptureCount = Double(max(0, min(1000, $0))) }
                        ), formatter: Self.countFormatter)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 40)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    if maxCaptureCount == 0 {
                        Text("0 = 無制限")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    if shutterService.activeMode == .interval {
                        progressBadge {
                            if shutterService.maxCaptureCount > 0 {
                                Text("キャプチャ回数: \(shutterService.captureCount)/\(shutterService.maxCaptureCount)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            } else {
                                Text("キャプチャ回数: \(shutterService.captureCount)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }

                    actionButton(
                        isActive: shutterService.activeMode == .interval,
                        startAction: { onStartInterval(selectedInterval, Int(maxCaptureCount)) },
                        stopAction: onStop
                    )
                }
            }

            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 12)

            // Change Detection
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("変化検知", icon: "eye", isActive: shutterService.activeMode == .changeDetection)

                    HStack(spacing: 6) {
                        Text("感度")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        Slider(value: $shutterService.sensitivity, in: 0.01...0.20, step: 0.01)
                            .controlSize(.small)
                            .tint(.cyan)
                        Text("\(Int(shutterService.sensitivity * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28)
                    }

                    if shutterService.activeMode == .changeDetection {
                        progressBadge {
                            Text("検知回数: \(shutterService.captureCount)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    actionButton(
                        isActive: shutterService.activeMode == .changeDetection,
                        startAction: onStartChangeDetection,
                        stopAction: onStop
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .frame(width: 240)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    // MARK: - Components

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, icon: String, isActive: Bool) -> some View {
        Label {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isActive
                        ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.white.opacity(0.9))
                )
        }
    }

    @ViewBuilder
    private func progressBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(Color.cyan.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    @ViewBuilder
    private func actionButton(isActive: Bool, startAction: @escaping () -> Void, stopAction: @escaping () -> Void) -> some View {
        Button(action: {
            if isActive {
                stopAction()
            } else {
                startAction()
            }
        }) {
            Text(isActive ? "停止" : "開始")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isActive
                                ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [.cyan, .blue.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        )
                )
                .shadow(color: isActive ? .red.opacity(0.4) : .cyan.opacity(0.4), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    // MARK: - Helpers

    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 1000
        f.allowsFloats = false
        return f
    }()

    private func intervalLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds / 60))分"
        } else if seconds == floor(seconds) {
            return "\(Int(seconds))秒"
        } else {
            return String(format: "%.1f秒", seconds)
        }
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
            onStartInterval: { [weak self] seconds, maxCount in
                self?.shutterService.startInterval(seconds: seconds, maxCount: maxCount)
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
        let width = max(fittingSize.width, 240)
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
        let panelSize = cachedSize ?? CGSize(width: 240, height: 300)

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
