import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case fullScreen = "全画面"
    case region = "範囲選択"
    case gifRecording = "GIF録画"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.dashed"
        case .region: return "viewfinder"
        case .gifRecording: return "record.circle"
        }
    }

    var hotkeyAction: HotkeyAction? {
        switch self {
        case .fullScreen: return .fullScreen
        case .region: return .region
        case .gifRecording: return .gifRecording
        }
    }

    var shortcut: String {
        hotkeyAction?.displayString ?? ""
    }
}
