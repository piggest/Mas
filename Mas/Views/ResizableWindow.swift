import AppKit
import Combine

// リサイズ状態を共有するためのクラス
class WindowResizeState: ObservableObject {
    static let shared = WindowResizeState()

    // ウィンドウoriginの変化量（スクリーン座標系）
    @Published var originDelta: CGPoint = .zero

    // ウィンドウが最初に作成された時のorigin（リセットされるまで保持）
    var originalWindowOrigin: CGPoint = .zero
    var isOriginalOriginSet: Bool = false

    // リサイズ開始時のoriginDelta（累積計算用）
    var originDeltaAtResizeStart: CGPoint = .zero

    // リサイズ開始時のウィンドウorigin
    var initialWindowOrigin: CGPoint = .zero

    func reset() {
        originDelta = .zero
        isOriginalOriginSet = false
    }

    func setOriginalOrigin(_ origin: CGPoint) {
        if !isOriginalOriginSet {
            originalWindowOrigin = origin
            isOriginalOriginSet = true
        }
    }
}

class ResizableWindow: NSWindow {
    private let resizeMargin: CGFloat = 8
    var passThroughEnabled: Bool = false {
        didSet {
            if passThroughEnabled {
                startPassThroughTracking()
            } else {
                stopPassThroughTracking()
                ignoresMouseEvents = false
            }
        }
    }
    private var passThroughLocalMonitor: Any?
    private var passThroughGlobalMonitor: Any?
    private var resizeMonitor: Any?
    private var isResizing: Bool = false
    private var resizeDirection: ResizeDirection?
    private var initialFrame: NSRect = .zero
    private var initialMouseLocation: NSPoint = .zero

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setupResizeMonitor()
    }

    private func setupResizeMonitor() {
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            guard event.window == self else { return event }

            switch event.type {
            case .leftMouseDown:
                return self.handleMouseDown(event)
            case .leftMouseDragged:
                return self.handleMouseDragged(event)
            case .leftMouseUp:
                return self.handleMouseUp(event)
            case .mouseMoved:
                self.handleMouseMoved(event)
                return event
            default:
                return event
            }
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = frame
        let localPoint = NSPoint(
            x: mouseLocation.x - windowFrame.origin.x,
            y: mouseLocation.y - windowFrame.origin.y
        )

        if let direction = detectResizeDirection(at: localPoint) {
            switch direction {
            case .top, .bottom:
                NSCursor.resizeUpDown.set()
            case .left, .right:
                NSCursor.resizeLeftRight.set()
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = frame
        let localPoint = NSPoint(
            x: mouseLocation.x - windowFrame.origin.x,
            y: mouseLocation.y - windowFrame.origin.y
        )

        if let direction = detectResizeDirection(at: localPoint) {
            isResizing = true
            resizeDirection = direction
            initialFrame = windowFrame
            initialMouseLocation = mouseLocation

            WindowResizeState.shared.setOriginalOrigin(windowFrame.origin)
            WindowResizeState.shared.originDeltaAtResizeStart = WindowResizeState.shared.originDelta
            WindowResizeState.shared.initialWindowOrigin = windowFrame.origin

            return nil
        }
        return event
    }

    private func handleMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard isResizing, let direction = resizeDirection else { return event }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y

        var newFrame = initialFrame

        switch direction {
        case .right:
            newFrame.size.width = max(50, initialFrame.width + deltaX)
        case .left:
            newFrame.size.width = max(50, initialFrame.width - deltaX)
            newFrame.origin.x = initialFrame.origin.x + initialFrame.width - newFrame.width
        case .top:
            newFrame.size.height = max(50, initialFrame.height + deltaY)
        case .bottom:
            newFrame.size.height = max(50, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + initialFrame.height - newFrame.height
        case .topRight:
            newFrame.size.width = max(50, initialFrame.width + deltaX)
            newFrame.size.height = max(50, initialFrame.height + deltaY)
        case .topLeft:
            newFrame.size.width = max(50, initialFrame.width - deltaX)
            newFrame.origin.x = initialFrame.origin.x + initialFrame.width - newFrame.width
            newFrame.size.height = max(50, initialFrame.height + deltaY)
        case .bottomRight:
            newFrame.size.width = max(50, initialFrame.width + deltaX)
            newFrame.size.height = max(50, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + initialFrame.height - newFrame.height
        case .bottomLeft:
            newFrame.size.width = max(50, initialFrame.width - deltaX)
            newFrame.origin.x = initialFrame.origin.x + initialFrame.width - newFrame.width
            newFrame.size.height = max(50, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + initialFrame.height - newFrame.height
        }

        setFrame(newFrame, display: true)

        // オフセット計算
        let currentXDelta = WindowResizeState.shared.initialWindowOrigin.x - newFrame.origin.x
        let initialTop = initialFrame.origin.y + initialFrame.height
        let newTop = newFrame.origin.y + newFrame.height
        let currentYDelta = newTop - initialTop

        let totalXDelta = round(WindowResizeState.shared.originDeltaAtResizeStart.x + currentXDelta)
        let totalYDelta = round(WindowResizeState.shared.originDeltaAtResizeStart.y + currentYDelta)

        WindowResizeState.shared.originDelta = CGPoint(x: totalXDelta, y: totalYDelta)

        return nil
    }

    private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
        if isResizing {
            isResizing = false
            resizeDirection = nil
            NSCursor.arrow.set()
            return nil
        }
        return event
    }

    private func detectResizeDirection(at point: NSPoint) -> ResizeDirection? {
        let onLeft = point.x < resizeMargin
        let onRight = point.x > frame.width - resizeMargin
        let onBottom = point.y < resizeMargin
        let onTop = point.y > frame.height - resizeMargin

        if onTop && onLeft { return .topLeft }
        if onTop && onRight { return .topRight }
        if onBottom && onLeft { return .bottomLeft }
        if onBottom && onRight { return .bottomRight }
        if onTop { return .top }
        if onBottom { return .bottom }
        if onLeft { return .left }
        if onRight { return .right }

        return nil
    }

    private func startPassThroughTracking() {
        passThroughLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
            return event
        }
        passThroughGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateIgnoresMouseEvents()
        }
    }

    private func stopPassThroughTracking() {
        if let monitor = passThroughLocalMonitor {
            NSEvent.removeMonitor(monitor)
            passThroughLocalMonitor = nil
        }
        if let monitor = passThroughGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            passThroughGlobalMonitor = nil
        }
    }

    private func updateIgnoresMouseEvents() {
        guard passThroughEnabled else { return }

        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = frame

        // マウスがウィンドウ外にある時はイベントを受け取る（メニュー等に影響しないように）
        guard windowFrame.contains(mouseLocation) else {
            ignoresMouseEvents = false
            return
        }

        // ウィンドウ座標に変換
        let localPoint = NSPoint(
            x: mouseLocation.x - windowFrame.origin.x,
            y: mouseLocation.y - windowFrame.origin.y
        )

        // 枠線部分（リサイズマージン）
        let onEdge = localPoint.x < resizeMargin ||
                     localPoint.x > windowFrame.width - resizeMargin ||
                     localPoint.y < resizeMargin ||
                     localPoint.y > windowFrame.height - resizeMargin

        // ボタンエリア（右上）
        let rightButtonRect = CGRect(
            x: windowFrame.width - 80,
            y: windowFrame.height - 50,
            width: 80,
            height: 50
        )

        // 閉じるボタンエリア（左上）
        let closeButtonRect = CGRect(
            x: 0,
            y: windowFrame.height - 50,
            width: 50,
            height: 50
        )

        let onButton = rightButtonRect.contains(localPoint) || closeButtonRect.contains(localPoint)

        ignoresMouseEvents = !(onEdge || onButton)
    }

    deinit {
        stopPassThroughTracking()
        if let monitor = resizeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // パススルー時でもボタンエリアはマウスイベントを受け取る
    func isInButtonArea(_ point: NSPoint) -> Bool {
        let buttonX = frame.width - 80
        let buttonY = frame.height - 40
        let buttonRect = CGRect(x: buttonX, y: buttonY, width: 80, height: 40)
        return buttonRect.contains(point)
    }

    enum ResizeDirection {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

// パススルー対応のコンテナビュー
class PassThroughContainerView: NSView {
    var passThroughEnabled: Bool = false
    private let resizeMargin: CGFloat = 8

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 現在のフレームサイズを取得（boundsではなくframeを使用）
        let viewWidth = frame.size.width
        let viewHeight = frame.size.height

        if passThroughEnabled {
            // 枠線部分（リサイズマージン）
            let onLeft = point.x < resizeMargin
            let onRight = point.x > viewWidth - resizeMargin
            let onTop = point.y > viewHeight - resizeMargin  // 左下原点なので上はheightに近い
            let onBottom = point.y < resizeMargin

            if onLeft || onRight || onTop || onBottom {
                return self
            }

            // ボタンエリア（右上）- 左下原点の座標系
            let rightButtonRect = CGRect(
                x: viewWidth - 80,
                y: viewHeight - 50,
                width: 80,
                height: 50
            )

            // 閉じるボタンエリア（左上）
            let closeButtonRect = CGRect(
                x: 0,
                y: viewHeight - 50,
                width: 50,
                height: 50
            )

            if rightButtonRect.contains(point) || closeButtonRect.contains(point) {
                return super.hitTest(point)
            }

            // それ以外はパススルー
            return nil
        }
        return super.hitTest(point)
    }
}
