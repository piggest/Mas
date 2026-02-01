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

        // 縁取り（黒い外縁 + 白い境界線）- マーカー以外
        if strokeEnabled && !isHighlighter {
            let blackPath = NSBezierPath()
            blackPath.lineWidth = path.lineWidth + 4
            blackPath.lineCapStyle = .round
            blackPath.lineJoinStyle = .round
            blackPath.move(to: points[0])
            for i in 1..<points.count {
                blackPath.line(to: points[i])
            }
            NSColor.black.withAlphaComponent(0.3).setStroke()
            blackPath.stroke()

            let whitePath = NSBezierPath()
            whitePath.lineWidth = path.lineWidth + 2
            whitePath.lineCapStyle = .round
            whitePath.lineJoinStyle = .round
            whitePath.move(to: points[0])
            for i in 1..<points.count {
                whitePath.line(to: points[i])
            }
            NSColor.white.setStroke()
            whitePath.stroke()
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
