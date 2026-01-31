import AppKit
import Foundation

class ArrowAnnotation: Annotation {
    let id = UUID()
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: NSColor
    var lineWidth: CGFloat

    init(startPoint: CGPoint, endPoint: CGPoint, color: NSColor = .systemRed, lineWidth: CGFloat = 3) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
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

        color.setFill()
        path.fill()
    }

    func contains(point: CGPoint) -> Bool {
        let distance = distanceFromPointToLine(point: point, lineStart: startPoint, lineEnd: endPoint)
        return distance < 10
    }

    private func distanceFromPointToLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = sqrt(dx * dx + dy * dy)

        if length == 0 {
            return sqrt(pow(point.x - lineStart.x, 2) + pow(point.y - lineStart.y, 2))
        }

        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (length * length)))
        let projectionX = lineStart.x + t * dx
        let projectionY = lineStart.y + t * dy

        return sqrt(pow(point.x - projectionX, 2) + pow(point.y - projectionY, 2))
    }
}
