import SwiftUI

// MARK: - SwiftUI ボタンスタイル

/// クリック時のハイライト効果を抑制した SwiftUI ボタンスタイル。
/// エディタ内のフロート系ボタン（クローズ・ピン・再キャプチャ等）で使用する。
struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

// MARK: - 編集モードのツール種別

/// エディタの編集モード（編集ツールバー）で選択可能なツール一覧。
/// `rawValue` は UI 表示・設定保存に使う日本語ラベル、`icon` は SF Symbols 名。
enum EditTool: String, CaseIterable {
    case move = "移動"
    case pen = "ペン"
    case highlight = "マーカー"
    case line = "直線"
    case arrow = "矢印"
    case arrowText = "矢印文字"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "文字"
    case mosaic = "ぼかし"
    case textSelection = "テキスト選択"
    case trim = "トリミング"

    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .arrowText: return "arrow.up.right.and.arrow.down.left.rectangle.fill"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .mosaic: return "drop.fill"
        case .textSelection: return "text.viewfinder"
        case .trim: return "square.dashed"
        }
    }
}

// MARK: - テキスト選択モードの内部表現

/// テキスト選択モードで OCR 結果から取り出した「1 文字」の位置情報。
/// 文字単位のヒット判定・矩形マージ・コピー範囲計算に使う。
struct FlatTextChar {
    /// 認識された文字。
    let character: Character
    /// SwiftUI 座標系（左上原点）での文字の矩形。
    let rect: CGRect
    /// この文字がブロック（行）末尾なら true。改行・行間判定に使う。
    let isBlockEnd: Bool
}

// MARK: - キャプチャアクション（右上ボタン）の種別

/// 右上の「再キャプチャ系」ボタンが現在表示しているアクション種別。
/// コンテキストメニューから切替可能。
enum CaptureActionMode: String, CaseIterable {
    case recapture = "再キャプチャ"
    case gif = "GIF録画"
    case video = "動画録画"

    var icon: String {
        switch self {
        case .recapture: return "camera.viewfinder"
        case .gif: return "record.circle"
        case .video: return "video.circle"
        }
    }
}
