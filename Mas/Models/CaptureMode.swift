import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case fullScreen = "全画面"
    case region = "範囲選択"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.dashed"
        case .region: return "viewfinder"
        }
    }

    var shortcut: String {
        switch self {
        case .fullScreen: return "⌘⇧3"
        case .region: return "⌘⇧4"
        }
    }
}
