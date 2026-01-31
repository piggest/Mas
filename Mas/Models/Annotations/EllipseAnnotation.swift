import AppKit
import Foundation

class EllipseAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var color: NSColor
    var lineWidth: CGFloat
    var isFilled: Bool
    var strokeEnabled: Bool

    init(rect: CGRect, color: NSColor = .systemRed, lineWidth: CGFloat = 2, isFilled: Bool = false, strokeEnabled: Bool = true) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.strokeEnabled = strokeEnabled
    }

    func draw(in bounds: NSRect) {
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth

        if isFilled {
            color.withAlphaComponent(0.3).setFill()
            path.fill()
        }

        // 縁取り（白い境界線）
        if strokeEnabled {
            let outerPath = NSBezierPath(ovalIn: rect)
            outerPath.lineWidth = lineWidth + 2
            NSColor.white.setStroke()
            outerPath.stroke()
        }

        color.setStroke()
        path.stroke()
    }

    func contains(point: CGPoint) -> Bool {
        let expandedRect = rect.insetBy(dx: -5, dy: -5)
        return expandedRect.contains(point)
    }

    func move(by delta: CGPoint) {
        rect = CGRect(x: rect.origin.x + delta.x, y: rect.origin.y + delta.y, width: rect.width, height: rect.height)
    }
}
