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
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        path.move(to: startPoint)
        path.line(to: endPoint)

        color.setStroke()
        path.stroke()

        drawArrowHead()
    }

    private func drawArrowHead() {
        let arrowLength: CGFloat = 15
        let arrowAngle: CGFloat = .pi / 6

        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)

        let point1 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        )

        let path = NSBezierPath()
        path.move(to: endPoint)
        path.line(to: point1)
        path.move(to: endPoint)
        path.line(to: point2)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        color.setStroke()
        path.stroke()
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
