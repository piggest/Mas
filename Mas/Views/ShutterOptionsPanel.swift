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

// MARK: - Shutter Mode Tab

enum ShutterTab: String, CaseIterable {
    case delayed = "時限"
    case interval = "インターバル"
    case changeDetection = "変化検知"

    var icon: String {
        switch self {
        case .delayed: return "timer"
        case .interval: return "arrow.triangle.2.circlepath"
        case .changeDetection: return "eye"
        }
    }
}

// MARK: - SwiftUI View

struct ShutterOptionsView: View {
    @ObservedObject var shutterService: ShutterService
    let onStartDelayed: (Int) -> Void
    let onStartInterval: (Double, Int) -> Void
    let onStartChangeDetection: () -> Void
    let onStop: () -> Void
    var onClose: (() -> Void)?
    var onSelectMonitorRegion: (() -> Void)?
    var onResetMonitorRegion: (() -> Void)?

    @State private var selectedTab: ShutterTab = .delayed
    @State private var selectedDelay: Double = 3
    @State private var selectedInterval: Double = 5
    @State private var maxCaptureCount: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab Bar + Close
            HStack(spacing: 4) {
                ForEach(ShutterTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(NoHighlightButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 12)

            // Content
            Group {
                switch selectedTab {
                case .delayed:
                    delayedContent
                case .interval:
                    intervalContent
                case .changeDetection:
                    changeDetectionContent
                }
            }
            .transaction { $0.animation = nil }
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

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(_ tab: ShutterTab) -> some View {
        let isSelected = selectedTab == tab
        let isActive = (tab == .delayed && shutterService.activeMode == .delayed)
            || (tab == .interval && shutterService.activeMode == .interval)
            || (tab == .changeDetection && shutterService.activeMode == .changeDetection)

        Button(action: { selectedTab = tab }) {
            HStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(
                isActive ? .cyan :
                isSelected ? .white :
                .white.opacity(0.5)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Color.cyan.opacity(0.5) :
                        isSelected ? Color.white.opacity(0.1) :
                        Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    // MARK: - Delayed Content

    private var delayedContent: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("時限シャッター", icon: "timer", isActive: shutterService.activeMode == .delayed)

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
        .padding(.bottom, 4)
    }

    // MARK: - Interval Content

    private var intervalContent: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("インターバルシャッター", icon: "arrow.triangle.2.circlepath", isActive: shutterService.activeMode == .interval)

                HStack(spacing: 6) {
                    Slider(value: $selectedInterval, in: 0.5...60, step: 0.5)
                        .controlSize(.small)
                        .tint(.cyan)
                    Text(intervalLabel(selectedInterval))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 38, alignment: .trailing)
                }

                HStack(spacing: 6) {
                    Text("回数")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, alignment: .leading)
                    Slider(value: $maxCaptureCount, in: 0...100, step: 1)
                        .controlSize(.small)
                        .tint(.cyan)
                    Text(maxCaptureCount == 0 ? "∞" : "\(Int(maxCaptureCount))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30, alignment: .trailing)
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
        .padding(.bottom, 4)
    }

    // MARK: - Change Detection Content

    private var changeDetectionContent: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("変化検知シャッター", icon: "eye", isActive: shutterService.activeMode == .changeDetection)

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

                // 監視範囲指定
                HStack(spacing: 6) {
                    if shutterService.monitorSubRect != nil {
                        Button(action: { onSelectMonitorRegion?() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 9))
                                Text("範囲指定中")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(NoHighlightButtonStyle())

                        Button(action: { onResetMonitorRegion?() }) {
                            Text("リセット")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(NoHighlightButtonStyle())
                    } else {
                        Button(action: { onSelectMonitorRegion?() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 9))
                                Text("監視範囲")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(NoHighlightButtonStyle())
                    }
                    Spacer()
                }

                if shutterService.activeMode == .changeDetection {
                    progressBadge {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("変化率:")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(String(format: "%.1f%%", shutterService.currentDiff * 100))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(shutterService.currentDiff > shutterService.sensitivity ? .orange : .cyan)
                                Text("/")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(String(format: "%.0f%%", shutterService.sensitivity * 100))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Text("検知回数: \(shutterService.captureCount)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
                        }
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
    var onCloseRequested: (() -> Void)?
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var cachedSize: CGSize?
    private var captureRegion: CGRect = .zero
    private let monitorRegionOverlay = MonitorRegionOverlay()
    private let monitorRegionIndicator = MonitorRegionIndicator()
    private var changeDetectionObserver: NSObjectProtocol?

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
                self.showIndicatorIfNeeded()
            },
            onStop: { [weak self] in
                self?.shutterService.stopAll()
                self?.monitorRegionIndicator.dismiss()
            },
            onClose: { [weak self] in
                self?.onCloseRequested?()
            },
            onSelectMonitorRegion: { [weak self] in
                self?.startMonitorRegionSelection()
            },
            onResetMonitorRegion: { [weak self] in
                self?.shutterService.monitorSubRect = nil
                self?.monitorRegionIndicator.dismiss()
            }
        )

        let width: CGFloat = 240
        let height: CGFloat = 260
        cachedSize = CGSize(width: width, height: height)
        let hosting = NSHostingView(rootView: panelView)
        hosting.layer?.isOpaque = false

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
        monitorRegionOverlay.dismiss()
        monitorRegionIndicator.dismiss()

        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let observer = changeDetectionObserver {
            NotificationCenter.default.removeObserver(observer)
            changeDetectionObserver = nil
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

    private func startMonitorRegionSelection() {
        guard let parent = parentWindow else { return }
        // SwiftUIのボタンコールバック内からウィンドウ生成すると不安定なので遅延実行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.monitorRegionOverlay.show(on: parent) { [weak self] normalizedRect in
                guard let self = self else { return }
                if let rect = normalizedRect {
                    self.shutterService.monitorSubRect = rect
                    self.showIndicatorIfNeeded()
                }
            }
        }
    }

    private func showIndicatorIfNeeded() {
        guard let parent = parentWindow,
              let subRect = shutterService.monitorSubRect else {
            monitorRegionIndicator.dismiss()
            return
        }
        monitorRegionIndicator.show(on: parent, normalizedRect: subRect)
    }
}

// MARK: - Monitor Region Overlay (ドラッグで監視サブ領域を選択)

private class MonitorRegionKeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
class MonitorRegionOverlay {
    private var overlayWindow: NSWindow?
    private weak var parentWindow: NSWindow?
    private var selectionView: MonitorRegionSelectionView?
    private var cursorPushed = false

    func show(on parentWindow: NSWindow, completion: @escaping (CGRect?) -> Void) {
        dismiss()
        self.parentWindow = parentWindow
        let parentFrame = parentWindow.frame

        let window = MonitorRegionKeyableWindow(
            contentRect: parentFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = MonitorRegionSelectionView(
            frame: NSRect(origin: .zero, size: parentFrame.size)
        ) { [weak self] rect in
            guard let self = self else { return }
            let normalized = CGRect(
                x: rect.origin.x / parentFrame.width,
                y: rect.origin.y / parentFrame.height,
                width: rect.width / parentFrame.width,
                height: rect.height / parentFrame.height
            )
            // dismiss後にcompletionを呼ぶ（ウィンドウ解放とコールバックを分離）
            self.dismiss()
            DispatchQueue.main.async {
                completion(normalized)
            }
        } onCancel: { [weak self] in
            self?.dismiss()
            DispatchQueue.main.async {
                completion(nil)
            }
        }
        self.selectionView = view

        window.contentView = view
        self.overlayWindow = window

        // 親の子ウィンドウとして追加（親のキー状態を維持）
        parentWindow.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        cursorPushed = true
        NSCursor.crosshair.push()
    }

    func dismiss() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let w = overlayWindow, let parent = parentWindow {
            parent.removeChildWindow(w)
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        selectionView = nil
    }
}

private class MonitorRegionSelectionView: NSView {
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect?
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateSelectionRect()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect = selectionRect, rect.width > 10, rect.height > 10 {
            onComplete(rect)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        }
    }

    private func updateSelectionRect() {
        guard let start = startPoint, let current = currentPoint else { return }
        selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 半透明オーバーレイ
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }

        // 選択領域をくり抜き
        NSColor.clear.set()
        rect.fill(using: .copy)

        // シアンの枠線
        NSColor.cyan.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // サイズ表示
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        var labelRect = CGRect(
            x: rect.midX - size.width / 2 - padding,
            y: rect.maxY + 6,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        if labelRect.maxY > bounds.maxY - 10 {
            labelRect.origin.y = rect.minY - labelRect.height - 6
        }
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + padding, y: labelRect.minY + padding / 2),
            withAttributes: attributes
        )
    }
}

// MARK: - Monitor Region Indicator (監視中のサブ領域枠線表示)

@MainActor
class MonitorRegionIndicator {
    private var indicatorWindow: NSWindow?

    func show(on parentWindow: NSWindow, normalizedRect: CGRect) {
        dismiss()

        let parentFrame = parentWindow.frame
        // 正規化座標→NS座標に変換（NSWindowは左下原点）
        let subX = parentFrame.origin.x + parentFrame.width * normalizedRect.origin.x
        let subY = parentFrame.origin.y + parentFrame.height * (1 - normalizedRect.origin.y - normalizedRect.height)
        let subW = parentFrame.width * normalizedRect.width
        let subH = parentFrame.height * normalizedRect.height

        let frame = NSRect(x: subX, y: subY, width: subW, height: subH)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = MonitorRegionBorderView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = borderView

        parentWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        self.indicatorWindow = window
    }

    func dismiss() {
        if let w = indicatorWindow {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
        }
        indicatorWindow = nil
    }

    func updatePosition(on parentWindow: NSWindow, normalizedRect: CGRect) {
        guard let window = indicatorWindow else { return }
        let parentFrame = parentWindow.frame
        let subX = parentFrame.origin.x + parentFrame.width * normalizedRect.origin.x
        let subY = parentFrame.origin.y + parentFrame.height * (1 - normalizedRect.origin.y - normalizedRect.height)
        let subW = parentFrame.width * normalizedRect.width
        let subH = parentFrame.height * normalizedRect.height
        window.setFrame(NSRect(x: subX, y: subY, width: subW, height: subH), display: true)
    }
}

private class MonitorRegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.cyan.withAlphaComponent(0.8).setStroke()
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}
