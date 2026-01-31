import AppKit
import Foundation

class FreehandAnnotation: Annotation {
    let id = UUID()
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var isHighlighter: Bool  // trueの場合は半透明マーカー

    init(points: [CGPoint] = [], color: NSColor = .systemRed, lineWidth: CGFloat = 3, isHighlighter: Bool = false) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isHighlighter = isHighlighter
    }

    func addPoint(_ point: CGPoint) {
        points.append(point)
    }

    func draw(in bounds: NSRect) {
        guard points.count >= 2 else { return }

        let path = NSBezierPath()
        path.lineWidth = isHighlighter ? lineWidth * 3 : lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }

        if isHighlighter {
            // マーカー: 半透明で描画
            color.withAlphaComponent(0.4).setStroke()
        } else {
            // 通常のペン
            color.setStroke()
        }
        path.stroke()
    }

    func contains(point: CGPoint) -> Bool {
        // 線の近くをタップしたかどうか
        for p in points {
            let distance = hypot(p.x - point.x, p.y - point.y)
            if distance < lineWidth + 5 {
                return true
            }
        }
        return false
    }
}
