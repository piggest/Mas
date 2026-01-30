import AppKit

class ResizableWindow: NSWindow {
    private let resizeMargin: CGFloat = 8
    var passThroughEnabled: Bool = false {
        didSet {
            if passThroughEnabled {
                startMouseTracking()
            } else {
                stopMouseTracking()
                ignoresMouseEvents = false
            }
        }
    }
    private var localMonitor: Any?
    private var globalMonitor: Any?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    private func startMouseTracking() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.updateIgnoresMouseEvents()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateIgnoresMouseEvents()
        }
    }

    private func stopMouseTracking() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
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
        stopMouseTracking()
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

    private func resizeDirection(for point: NSPoint) -> ResizeDirection? {
        let frame = self.frame
        let localPoint = point

        let onLeft = localPoint.x < resizeMargin
        let onRight = localPoint.x > frame.width - resizeMargin
        let onBottom = localPoint.y < resizeMargin
        let onTop = localPoint.y > frame.height - resizeMargin

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

    override func mouseMoved(with event: NSEvent) {
        let point = event.locationInWindow
        if let direction = resizeDirection(for: point) {
            switch direction {
            case .top, .bottom:
                NSCursor.resizeUpDown.set()
            case .left, .right:
                NSCursor.resizeLeftRight.set()
            case .topLeft, .bottomRight:
                NSCursor.crosshair.set() // macOSには対角リサイズカーソルがない
            case .topRight, .bottomLeft:
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow

        if let direction = resizeDirection(for: point) {
            performResize(direction: direction, with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func performResize(direction: ResizeDirection, with event: NSEvent) {
        let initialFrame = self.frame
        let initialMouseLocation = NSEvent.mouseLocation

        while true {
            guard let nextEvent = NSApp.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture, inMode: .eventTracking, dequeue: true) else { break }

            if nextEvent.type == .leftMouseUp {
                break
            }

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

            self.setFrame(newFrame, display: true)
        }

        NSCursor.arrow.set()
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
        if passThroughEnabled {
            // 枠線部分（リサイズマージン）
            let onLeft = point.x < resizeMargin
            let onRight = point.x > bounds.width - resizeMargin
            let onTop = point.y > bounds.height - resizeMargin  // 左下原点なので上はheightに近い
            let onBottom = point.y < resizeMargin

            if onLeft || onRight || onTop || onBottom {
                return self
            }

            // ボタンエリア（右上）- 左下原点の座標系
            let rightButtonRect = CGRect(
                x: bounds.width - 80,
                y: bounds.height - 50,
                width: 80,
                height: 50
            )

            // 閉じるボタンエリア（左上）
            let closeButtonRect = CGRect(
                x: 0,
                y: bounds.height - 50,
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
