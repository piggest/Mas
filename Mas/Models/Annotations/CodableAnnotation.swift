import AppKit
import Foundation

struct CodableAnnotation: Codable {
    enum Kind: String, Codable {
        case arrow, rect, ellipse, text, highlight, freehand, mosaic
    }

    let kind: Kind

    // Color (RGBA)
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let colorA: Double

    // Common
    let lineWidth: Double?
    let strokeEnabled: Bool?

    // Rect-based (rect, ellipse, highlight, mosaic)
    let rectX: Double?
    let rectY: Double?
    let rectW: Double?
    let rectH: Double?
    let isFilled: Bool?

    // Arrow
    let startX: Double?
    let startY: Double?
    let endX: Double?
    let endY: Double?

    // Text
    let posX: Double?
    let posY: Double?
    let text: String?
    let fontSize: Double?

    // Freehand
    let points: [[Double]]?
    let isHighlighter: Bool?

    // Mosaic
    let pixelSize: Int?

    // MARK: - Annotation → CodableAnnotation

    static func from(_ annotation: any Annotation) -> CodableAnnotation? {
        if let a = annotation as? ArrowAnnotation {
            let c = colorComponents(a.color)
            return CodableAnnotation(
                kind: .arrow, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: Double(a.lineWidth), strokeEnabled: a.strokeEnabled,
                rectX: nil, rectY: nil, rectW: nil, rectH: nil, isFilled: nil,
                startX: Double(a.startPoint.x), startY: Double(a.startPoint.y),
                endX: Double(a.endPoint.x), endY: Double(a.endPoint.y),
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: nil, isHighlighter: nil, pixelSize: nil
            )
        }
        if let a = annotation as? RectAnnotation {
            let c = colorComponents(a.color)
            return CodableAnnotation(
                kind: .rect, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: Double(a.lineWidth), strokeEnabled: a.strokeEnabled,
                rectX: Double(a.rect.origin.x), rectY: Double(a.rect.origin.y),
                rectW: Double(a.rect.width), rectH: Double(a.rect.height),
                isFilled: a.isFilled,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: nil, isHighlighter: nil, pixelSize: nil
            )
        }
        if let a = annotation as? EllipseAnnotation {
            let c = colorComponents(a.color)
            return CodableAnnotation(
                kind: .ellipse, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: Double(a.lineWidth), strokeEnabled: a.strokeEnabled,
                rectX: Double(a.rect.origin.x), rectY: Double(a.rect.origin.y),
                rectW: Double(a.rect.width), rectH: Double(a.rect.height),
                isFilled: a.isFilled,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: nil, isHighlighter: nil, pixelSize: nil
            )
        }
        if let a = annotation as? TextAnnotation {
            let c = colorComponents(a.color)
            return CodableAnnotation(
                kind: .text, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: nil, strokeEnabled: a.strokeEnabled,
                rectX: nil, rectY: nil, rectW: nil, rectH: nil, isFilled: nil,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: Double(a.position.x), posY: Double(a.position.y),
                text: a.text, fontSize: Double(a.font.pointSize),
                points: nil, isHighlighter: nil, pixelSize: nil
            )
        }
        if let a = annotation as? HighlightAnnotation {
            let c = colorComponents(a.color)
            return CodableAnnotation(
                kind: .highlight, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: nil, strokeEnabled: nil,
                rectX: Double(a.rect.origin.x), rectY: Double(a.rect.origin.y),
                rectW: Double(a.rect.width), rectH: Double(a.rect.height),
                isFilled: nil,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: nil, isHighlighter: nil, pixelSize: nil
            )
        }
        if let a = annotation as? FreehandAnnotation {
            let c = colorComponents(a.color)
            let pts = a.points.map { [Double($0.x), Double($0.y)] }
            return CodableAnnotation(
                kind: .freehand, colorR: c.r, colorG: c.g, colorB: c.b, colorA: c.a,
                lineWidth: Double(a.lineWidth), strokeEnabled: a.strokeEnabled,
                rectX: nil, rectY: nil, rectW: nil, rectH: nil, isFilled: nil,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: pts, isHighlighter: a.isHighlighter, pixelSize: nil
            )
        }
        if let a = annotation as? MosaicAnnotation {
            return CodableAnnotation(
                kind: .mosaic, colorR: 0, colorG: 0, colorB: 0, colorA: 1,
                lineWidth: nil, strokeEnabled: nil,
                rectX: Double(a.rect.origin.x), rectY: Double(a.rect.origin.y),
                rectW: Double(a.rect.width), rectH: Double(a.rect.height),
                isFilled: nil,
                startX: nil, startY: nil, endX: nil, endY: nil,
                posX: nil, posY: nil, text: nil, fontSize: nil,
                points: nil, isHighlighter: nil, pixelSize: a.pixelSize
            )
        }
        return nil
    }

    // MARK: - CodableAnnotation → Annotation

    func toAnnotation(sourceImage: NSImage? = nil) -> (any Annotation)? {
        let color = NSColor(red: colorR, green: colorG, blue: colorB, alpha: colorA)

        switch kind {
        case .arrow:
            guard let sx = startX, let sy = startY, let ex = endX, let ey = endY else { return nil }
            return ArrowAnnotation(
                startPoint: CGPoint(x: sx, y: sy),
                endPoint: CGPoint(x: ex, y: ey),
                color: color,
                lineWidth: CGFloat(lineWidth ?? 3),
                strokeEnabled: strokeEnabled ?? true
            )
        case .rect:
            guard let rx = rectX, let ry = rectY, let rw = rectW, let rh = rectH else { return nil }
            return RectAnnotation(
                rect: CGRect(x: rx, y: ry, width: rw, height: rh),
                color: color,
                lineWidth: CGFloat(lineWidth ?? 2),
                isFilled: isFilled ?? false,
                strokeEnabled: strokeEnabled ?? true
            )
        case .ellipse:
            guard let rx = rectX, let ry = rectY, let rw = rectW, let rh = rectH else { return nil }
            return EllipseAnnotation(
                rect: CGRect(x: rx, y: ry, width: rw, height: rh),
                color: color,
                lineWidth: CGFloat(lineWidth ?? 2),
                isFilled: isFilled ?? false,
                strokeEnabled: strokeEnabled ?? true
            )
        case .text:
            guard let px = posX, let py = posY, let t = text else { return nil }
            let size = CGFloat(fontSize ?? 16)
            return TextAnnotation(
                position: CGPoint(x: px, y: py),
                text: t,
                font: .systemFont(ofSize: size, weight: .medium),
                color: color,
                strokeEnabled: strokeEnabled ?? true
            )
        case .highlight:
            guard let rx = rectX, let ry = rectY, let rw = rectW, let rh = rectH else { return nil }
            return HighlightAnnotation(
                rect: CGRect(x: rx, y: ry, width: rw, height: rh),
                color: color
            )
        case .freehand:
            guard let pts = points else { return nil }
            let cgPoints = pts.compactMap { p -> CGPoint? in
                guard p.count == 2 else { return nil }
                return CGPoint(x: p[0], y: p[1])
            }
            return FreehandAnnotation(
                points: cgPoints,
                color: color,
                lineWidth: CGFloat(lineWidth ?? 3),
                isHighlighter: isHighlighter ?? false,
                strokeEnabled: strokeEnabled ?? true
            )
        case .mosaic:
            guard let rx = rectX, let ry = rectY, let rw = rectW, let rh = rectH else { return nil }
            let mosaic = MosaicAnnotation(
                rect: CGRect(x: rx, y: ry, width: rw, height: rh),
                pixelSize: pixelSize ?? 10,
                sourceImage: sourceImage
            )
            mosaic.isDrawing = false
            return mosaic
        }
    }

    // MARK: - Helper

    private static func colorComponents(_ color: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }
}
