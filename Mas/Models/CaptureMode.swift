import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case fullScreen = "全画面"
    case region = "範囲選択"
    case gifRecording = "GIF録画"
    case videoRecording = "動画撮影"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.dashed"
        case .region: return "viewfinder"
        case .gifRecording: return "record.circle"
        case .videoRecording: return "video.circle"
        }
    }

    var hotkeyAction: HotkeyAction? {
        switch self {
        case .fullScreen: return .fullScreen
        case .region: return .region
        case .gifRecording: return .gifRecording
        case .videoRecording: return .videoRecording
        }
    }

    var shortcut: String {
        hotkeyAction?.displayString ?? ""
    }
}
