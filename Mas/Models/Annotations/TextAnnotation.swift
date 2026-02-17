import AppKit
import Foundation

class TextAnnotation: Annotation {
    let id = UUID()
    var position: CGPoint
    var text: String
    var font: NSFont
    var color: NSColor
    var strokeEnabled: Bool

    init(position: CGPoint, text: String = "", font: NSFont = .systemFont(ofSize: 16, weight: .medium), color: NSColor = .systemRed, strokeEnabled: Bool = true) {
        self.position = position
        self.text = text
        self.font = font
        self.color = color
        self.strokeEnabled = strokeEnabled
    }

    func copy() -> TextAnnotation {
        return TextAnnotation(
            position: position,
            text: text,
            font: font.copy() as? NSFont ?? font,
            color: color.copy() as? NSColor ?? color,
            strokeEnabled: strokeEnabled
        )
    }

    func draw(in rect: NSRect) {
        let drawPosition = CGPoint(x: position.x, y: position.y - font.ascender)

        if strokeEnabled {
            // 3パス描画：黒い外縁 → 白い縁取り → 元の色
            // パス1: 黒いアウトライン（最も太い）
            let outerStrokeAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: NSColor.black.withAlphaComponent(0.5),
                .strokeWidth: 10.0
            ]
            let outerStrokeString = NSAttributedString(string: text, attributes: outerStrokeAttributes)
            outerStrokeString.draw(at: drawPosition)

            // パス2: 白いストローク（中間）
            let strokeAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: NSColor.white,
                .strokeWidth: 6.0
            ]
            let strokeString = NSAttributedString(string: text, attributes: strokeAttributes)
            strokeString.draw(at: drawPosition)

            // パス3: 元の色で塗りつぶし
            let fillAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let fillString = NSAttributedString(string: text, attributes: fillAttributes)
            fillString.draw(at: drawPosition)
        } else {
            // 縁取りなし
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            attributedString.draw(at: drawPosition)
        }
    }

    func contains(point: CGPoint) -> Bool {
        let rect = boundingRect()
        return rect.contains(point)
    }

    func boundingRect() -> CGRect {
        let size = textSize()
        let drawOrigin = CGPoint(x: position.x, y: position.y - font.ascender)
        return CGRect(origin: drawOrigin, size: size)
    }

    func textSize() -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size
    }

    func move(by delta: CGPoint) {
        position = CGPoint(x: position.x + delta.x, y: position.y + delta.y)
    }

    // 属性アクセス
    var annotationColor: NSColor? {
        get { color }
        set { if let c = newValue { color = c } }
    }
    var annotationLineWidth: CGFloat? {
        get { font.pointSize / 5 }
        set { if let size = newValue { font = NSFont.systemFont(ofSize: size * 5, weight: .medium) } }
    }
    var annotationStrokeEnabled: Bool? {
        get { strokeEnabled }
        set { if let s = newValue { strokeEnabled = s } }
    }
}
