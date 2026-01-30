import AppKit
import Foundation

class TextAnnotation: Annotation {
    let id = UUID()
    var position: CGPoint
    var text: String
    var font: NSFont
    var color: NSColor

    init(position: CGPoint, text: String = "", font: NSFont = .systemFont(ofSize: 16, weight: .medium), color: NSColor = .systemRed) {
        self.position = position
        self.text = text
        self.font = font
        self.color = color
    }

    func draw(in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        // positionをテキストの左上として扱う
        // draw(at:)はベースライン左端基準なので、ascender分下げる
        let drawPosition = CGPoint(x: position.x, y: position.y - font.ascender)
        attributedString.draw(at: drawPosition)
    }

    func contains(point: CGPoint) -> Bool {
        let size = textSize()
        let rect = CGRect(origin: position, size: size)
        return rect.contains(point)
    }

    func textSize() -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size
    }
}
