import Foundation

class HistoryService {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let masDir = appSupport.appendingPathComponent("Mas")
        fileURL = masDir.appendingPathComponent("history.json")

        // ディレクトリがなければ作成
        if !FileManager.default.fileExists(atPath: masDir.path) {
            try? FileManager.default.createDirectory(at: masDir, withIntermediateDirectories: true)
        }
    }

    func load() -> [ScreenshotHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScreenshotHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ScreenshotHistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addEntry(_ entry: ScreenshotHistoryEntry) {
        var entries = load()
        entries.insert(entry, at: 0)
        save(entries)
    }

    func removeEntry(id: UUID) {
        var entries = load()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func updateEntry(_ updated: ScreenshotHistoryEntry) {
        var entries = load()
        if let index = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[index] = updated
        } else if let index = entries.firstIndex(where: { $0.filePath == updated.filePath }) {
            entries[index] = updated
        }
        save(entries)
    }

    func updateAnnotations(forFilePath filePath: String, annotations: [CodableAnnotation]?, baseFilePath: String?) {
        var entries = load()
        if let index = entries.firstIndex(where: { $0.filePath == filePath }) {
            entries[index].annotations = annotations
            entries[index].baseFilePath = baseFilePath
            save(entries)
        }
    }

    func removeInvalidEntries() -> [ScreenshotHistoryEntry] {
        var entries = load()
        entries.removeAll { !$0.fileExists }
        save(entries)
        return entries
    }
}
