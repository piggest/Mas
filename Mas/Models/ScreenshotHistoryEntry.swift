import Foundation

struct ScreenshotHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let mode: String        // "全画面" or "範囲選択"
    let filePath: String    // 保存先ファイルパス
    let width: Int
    let height: Int

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}
