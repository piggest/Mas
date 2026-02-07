import Foundation

struct ScreenshotHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let mode: String        // "全画面" or "範囲選択"
    let filePath: String    // 保存先ファイルパス
    let width: Int
    let height: Int
    let windowX: Double?    // キャプチャ時のウィンドウ位置X（スクリーン座標・左上原点）
    let windowY: Double?    // キャプチャ時のウィンドウ位置Y
    let windowW: Double?    // キャプチャ時のウィンドウ幅
    let windowH: Double?    // キャプチャ時のウィンドウ高さ
    var baseFilePath: String?               // アノテーション適用前の元画像パス
    var hasAnnotations: Bool?               // アノテーションデータが存在するか
    var isFavorite: Bool?                   // お気に入り

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}
