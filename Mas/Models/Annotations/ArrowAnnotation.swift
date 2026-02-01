import AppKit
import Foundation

class ArrowAnnotation: Annotation {
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
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)

        // 矢印頭のサイズ（lineWidthに比例）- 鋭い形状
        let headLength: CGFloat = lineWidth * 7
        let headWidth: CGFloat = lineWidth * 2.5

        // シャフトの太さ（尻尾は細く、頭に向かって太くなるテーパー形状）
        let tailWidth: CGFloat = lineWidth * 0.3  // 尻尾は細い
        let shaftEndWidth: CGFloat = lineWidth * 1.2  // 頭の根元は太め

        // 矢印頭の根元の位置
        let headBase = CGPoint(
            x: endPoint.x - headLength * cos(angle),
            y: endPoint.y - headLength * sin(angle)
        )

        // 矢印全体を一つの塗りつぶしパスで描画
        let path = NSBezierPath()

        // 垂直方向の角度
        let perpAngle = angle + .pi / 2

        // 尻尾（開始点）- 細い
        let tailLeft = CGPoint(
            x: startPoint.x + tailWidth * cos(perpAngle),
            y: startPoint.y + tailWidth * sin(perpAngle)
        )
        let tailRight = CGPoint(
            x: startPoint.x - tailWidth * cos(perpAngle),
            y: startPoint.y - tailWidth * sin(perpAngle)
        )

        // シャフトの終端（矢印頭の根元）- 太い
        let shaftEnd1 = CGPoint(
            x: headBase.x + shaftEndWidth * cos(perpAngle),
            y: headBase.y + shaftEndWidth * sin(perpAngle)
        )
        let shaftEnd2 = CGPoint(
            x: headBase.x - shaftEndWidth * cos(perpAngle),
            y: headBase.y - shaftEndWidth * sin(perpAngle)
        )

        // 矢印頭の両端
        let headLeft = CGPoint(
            x: headBase.x + headWidth * cos(perpAngle),
            y: headBase.y + headWidth * sin(perpAngle)
        )
        let headRight = CGPoint(
            x: headBase.x - headWidth * cos(perpAngle),
            y: headBase.y - headWidth * sin(perpAngle)
        )

        // パスを構築（テーパー形状）
        path.move(to: tailLeft)
        path.line(to: shaftEnd1)
        path.line(to: headLeft)
        path.line(to: endPoint)
        path.line(to: headRight)
        path.line(to: shaftEnd2)
        path.line(to: tailRight)
        path.close()

        // 縁取り（白い境界線）
        if strokeEnabled {
            NSColor.white.setStroke()
            path.lineWidth = lineWidth * 0.4
            path.stroke()
        }

        color.setFill()
        path.fill()
    }

    func contains(point: CGPoint) -> Bool {
        // 矢印を囲む矩形で判定
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
