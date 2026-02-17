import AppKit
import Foundation

protocol Annotation: Identifiable {
    var id: UUID { get }
    func draw(in rect: NSRect)
    func contains(point: CGPoint) -> Bool
    func boundingRect() -> CGRect
    func move(by delta: CGPoint)

    // 属性変更用（オプショナル）
    var annotationColor: NSColor? { get set }
    var annotationLineWidth: CGFloat? { get set }
    var annotationStrokeEnabled: Bool? { get set }
}

// デフォルト実装（属性を持たないアノテーション用）
extension Annotation {
    var annotationColor: NSColor? {
        get { nil }
        set { }
    }
    var annotationLineWidth: CGFloat? {
        get { nil }
        set { }
    }
    var annotationStrokeEnabled: Bool? {
        get { nil }
        set { }
    }
}

enum AnnotationType: String, CaseIterable, Identifiable {
    case line = "直線"
    case arrow = "矢印"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "テキスト"
    case highlight = "ハイライト"
    case mosaic = "モザイク"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3"
        }
    }
}
