import AppKit
import Foundation

class RectAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var color: NSColor
    var lineWidth: CGFloat
    var isFilled: Bool

    init(rect: CGRect, color: NSColor = .systemRed, lineWidth: CGFloat = 2, isFilled: Bool = false) {
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
    }

    func draw(in bounds: NSRect) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth

        if isFilled {
            color.withAlphaComponent(0.3).setFill()
            path.fill()
        }

        color.setStroke()
        path.stroke()
    }

    func contains(point: CGPoint) -> Bool {
        let expandedRect = rect.insetBy(dx: -5, dy: -5)
        return expandedRect.contains(point)
    }
}
