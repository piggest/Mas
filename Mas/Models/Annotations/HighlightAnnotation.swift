import AppKit
import Foundation

class HighlightAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var color: NSColor

    init(rect: CGRect, color: NSColor = .systemYellow) {
        self.rect = rect
        self.color = color
    }

    func draw(in bounds: NSRect) {
        color.withAlphaComponent(0.4).setFill()
        let path = NSBezierPath(rect: rect)
        path.fill()
    }

    func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
    }

    func move(by delta: CGPoint) {
        rect = CGRect(x: rect.origin.x + delta.x, y: rect.origin.y + delta.y, width: rect.width, height: rect.height)
    }
}
