import Foundation

class HistoryService {
    private let fileURL: URL
    private let annotationsDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let masDir = appSupport.appendingPathComponent("Mas")
        fileURL = masDir.appendingPathComponent("history.json")
        annotationsDir = masDir.appendingPathComponent("annotations")

        // ディレクトリがなければ作成
        for dir in [masDir, annotationsDir] {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        // 既存データからアノテーションを分離（マイグレーション）
        migrateAnnotations()
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
        // アノテーションファイルも削除
        removeAnnotationFile(id: id)
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

    // MARK: - アノテーション（個別ファイル管理）

    private func annotationFileURL(id: UUID) -> URL {
        annotationsDir.appendingPathComponent("\(id.uuidString).json")
    }

    func saveAnnotations(id: UUID, annotations: [CodableAnnotation]) {
        let url = annotationFileURL(id: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(annotations) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadAnnotations(id: UUID) -> [CodableAnnotation]? {
        let url = annotationFileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode([CodableAnnotation].self, from: data)
    }

    func removeAnnotationFile(id: UUID) {
        let url = annotationFileURL(id: id)
        try? FileManager.default.removeItem(at: url)
    }

    func updateAnnotations(forFilePath filePath: String, annotations: [CodableAnnotation]?, baseFilePath: String?) {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.filePath == filePath }) else { return }
        let entryID = entries[index].id

        if let annotations = annotations, !annotations.isEmpty {
            saveAnnotations(id: entryID, annotations: annotations)
            entries[index].hasAnnotations = true
        } else {
            removeAnnotationFile(id: entryID)
            entries[index].hasAnnotations = nil
        }
        entries[index].baseFilePath = baseFilePath
        save(entries)
    }

    func removeInvalidEntries() -> [ScreenshotHistoryEntry] {
        var entries = load()
        let removed = entries.filter { !$0.fileExists }
        for entry in removed {
            removeAnnotationFile(id: entry.id)
        }
        entries.removeAll { !$0.fileExists }
        save(entries)
        return entries
    }

    // MARK: - マイグレーション（旧形式からの移行）

    private func migrateAnnotations() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        var needsMigration = false
        for item in json {
            if item["annotations"] != nil {
                needsMigration = true
                break
            }
        }
        guard needsMigration else { return }

        // 旧形式を読み込み
        struct LegacyEntry: Codable {
            let id: UUID
            let timestamp: Date
            let mode: String
            let filePath: String
            let width: Int
            let height: Int
            let windowX: Double?
            let windowY: Double?
            let windowW: Double?
            let windowH: Double?
            var annotations: [CodableAnnotation]?
            var baseFilePath: String?
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacyEntries = try? decoder.decode([LegacyEntry].self, from: data) else { return }

        var newEntries: [ScreenshotHistoryEntry] = []
        for legacy in legacyEntries {
            // アノテーションを個別ファイルに保存
            if let annotations = legacy.annotations, !annotations.isEmpty {
                saveAnnotations(id: legacy.id, annotations: annotations)
            }

            let entry = ScreenshotHistoryEntry(
                id: legacy.id,
                timestamp: legacy.timestamp,
                mode: legacy.mode,
                filePath: legacy.filePath,
                width: legacy.width,
                height: legacy.height,
                windowX: legacy.windowX,
                windowY: legacy.windowY,
                windowW: legacy.windowW,
                windowH: legacy.windowH,
                baseFilePath: legacy.baseFilePath,
                hasAnnotations: (legacy.annotations != nil && !legacy.annotations!.isEmpty) ? true : nil
            )
            newEntries.append(entry)
        }
        save(newEntries)
    }
}
