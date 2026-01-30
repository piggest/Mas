import AppKit
import UniformTypeIdentifiers

@MainActor
class FileStorageService {

    enum ImageFormat: String, CaseIterable {
        case png = "PNG"
        case jpeg = "JPEG"

        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            }
        }

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            }
        }
    }

    func saveImage(_ image: NSImage, format: ImageFormat = .png, quality: CGFloat = 0.9) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = generateFilename(format: format)
        panel.canCreateDirectories = true

        let response = await panel.begin()

        guard response == .OK, let url = panel.url else {
            return nil
        }

        do {
            try saveImageToURL(image, url: url, format: format, quality: quality)
            return url
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    func saveImageToDefaultLocation(_ image: NSImage, format: ImageFormat = .png, quality: CGFloat = 0.9) throws -> URL {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let filename = generateFilename(format: format)
        let url = desktopURL.appendingPathComponent(filename)

        try saveImageToURL(image, url: url, format: format, quality: quality)
        return url
    }

    func autoSaveImage(_ image: NSImage, format: ImageFormat = .png, quality: CGFloat = 0.9) throws -> URL {
        let saveFolder = getSaveFolder()

        // フォルダが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: saveFolder.path) {
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        }

        let filename = generateFilename(format: format)
        let url = saveFolder.appendingPathComponent(filename)

        try saveImageToURL(image, url: url, format: format, quality: quality)
        return url
    }

    func getSaveFolder() -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: "autoSaveFolder"),
           !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath)
        }
        // デフォルトはピクチャフォルダ内のMasフォルダ
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        return picturesURL.appendingPathComponent("Mas")
    }

    func setSaveFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "autoSaveFolder")
    }

    private func saveImageToURL(_ image: NSImage, url: URL, format: ImageFormat, quality: CGFloat) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw StorageError.invalidImageData
        }

        let properties: [NSBitmapImageRep.PropertyKey: Any]
        let fileType: NSBitmapImageRep.FileType

        switch format {
        case .png:
            properties = [:]
            fileType = .png
        case .jpeg:
            properties = [.compressionFactor: quality]
            fileType = .jpeg
        }

        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw StorageError.encodingFailed
        }

        try data.write(to: url)
    }

    private func generateFilename(format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Screenshot_\(timestamp).\(format.fileExtension)"
    }
}

enum StorageError: Error, LocalizedError {
    case invalidImageData
    case encodingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "画像データが無効です"
        case .encodingFailed:
            return "画像のエンコードに失敗しました"
        case .saveFailed:
            return "保存に失敗しました"
        }
    }
}
