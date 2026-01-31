import AppKit
import Foundation

class FreehandAnnotation: Annotation {
    let id = UUID()
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var isHighlighter: Bool  // trueの場合は半透明マーカー
    var strokeEnabled: Bool

    init(points: [CGPoint] = [], color: NSColor = .systemRed, lineWidth: CGFloat = 3, isHighlighter: Bool = false, strokeEnabled: Bool = true) {
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.isHighlighter = isHighlighter
        self.strokeEnabled = strokeEnabled
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

        // 縁取り（白い境界線）- マーカー以外
        if strokeEnabled && !isHighlighter {
            let outerPath = NSBezierPath()
            outerPath.lineWidth = path.lineWidth + 2
            outerPath.lineCapStyle = .round
            outerPath.lineJoinStyle = .round
            outerPath.move(to: points[0])
            for i in 1..<points.count {
                outerPath.line(to: points[i])
            }
            NSColor.white.setStroke()
            outerPath.stroke()
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
        // 描画範囲の矩形で判定
        let boundingRect = self.boundingRect()
        return boundingRect.contains(point)
    }

    func boundingRect() -> CGRect {
        guard !points.isEmpty else { return .zero }
        let minX = points.map { $0.x }.min()! - lineWidth
        let minY = points.map { $0.y }.min()! - lineWidth
        let maxX = points.map { $0.x }.max()! + lineWidth
        let maxY = points.map { $0.y }.max()! + lineWidth
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func move(by delta: CGPoint) {
        points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
    }
}
