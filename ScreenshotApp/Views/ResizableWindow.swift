import AppKit

class ResizableWindow: NSWindow {
    private let resizeMargin: CGFloat = 8

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
