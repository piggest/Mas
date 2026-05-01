import AppKit
import Foundation

class LineAnnotation: Annotation {
    let id = UUID()
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var strokeEnabled: Bool

    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = .systemRed, lineWidth: CGFloat = 3, strokeEnabled: Bool = true) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.strokeEnabled = strokeEnabled
    }

    func draw(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: startPoint)
        path.line(to: endPoint)
        path.lineCapStyle = .round

        // 縁取り（黒い外縁 → 白い境界線 → 色の線）
        if strokeEnabled {
            NSColor.black.withAlphaComponent(0.3).setStroke()
            path.lineWidth = lineWidth + 4
            path.stroke()

            NSColor.white.setStroke()
            path.lineWidth = lineWidth + 2
            path.stroke()
        }

        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    func contains(point: CGPoint) -> Bool {
        let boundingRect = self.boundingRect()
        return boundingRect.contains(point)
    }

    func boundingRect() -> CGRect {
        let minX = min(startPoint.x, endPoint.x) - lineWidth * 3
        let minY = min(startPoint.y, endPoint.y) - lineWidth * 3
        let maxX = max(startPoint.x, endPoint.x) + lineWidth * 3
        let maxY = max(startPoint.y, endPoint.y) + lineWidth * 3
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func move(by delta: CGPoint) {
        startPoint = CGPoint(x: startPoint.x + delta.x, y: startPoint.y + delta.y)
        endPoint = CGPoint(x: endPoint.x + delta.x, y: endPoint.y + delta.y)
    }

    // 属性アクセス
    var annotationColor: NSColor? {
        get { color }
        set { if let c = newValue { color = c } }
    }
    var annotationLineWidth: CGFloat? {
        get { lineWidth }
        set { if let w = newValue { lineWidth = w } }
    }
    var annotationStrokeEnabled: Bool? {
        get { strokeEnabled }
        set { if let s = newValue { strokeEnabled = s } }
    }
}
