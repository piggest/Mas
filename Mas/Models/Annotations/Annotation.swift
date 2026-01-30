import AppKit
import Foundation

protocol Annotation: Identifiable {
    var id: UUID { get }
    func draw(in rect: NSRect)
    func contains(point: CGPoint) -> Bool
}

enum AnnotationType: String, CaseIterable, Identifiable {
    case arrow = "矢印"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "テキスト"
    case highlight = "ハイライト"
    case mosaic = "モザイク"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3"
        }
    }
}
