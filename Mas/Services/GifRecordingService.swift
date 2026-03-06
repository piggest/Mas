import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
class GifRecordingService {
    private var frameCount: Int = 0
    private var tempDirectory: URL?
    private var timer: DispatchSourceTimer?
    private var region: CGRect = .zero
    private(set) var isRecording = false
    private(set) var isGenerating = false
    private(set) var generationProgress: Double = 0
    private var startTime: Date?
    private let captureService = ScreenCaptureService()
    private let frameInterval: Double = 0.1  // 10fps

    var elapsedTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    func startRecording(region: CGRect) {
        self.region = region
        self.frameCount = 0
        self.isRecording = true
        self.startTime = Date()

        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MasGifFrames-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempDirectory = tempDir

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: frameInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.captureFrame()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        timer?.cancel()
        timer = nil
        isRecording = false

        guard frameCount > 0, let tempDir = tempDirectory else {
            cleanupTempDirectory()
            return nil
        }
        let url = generateOutputURL()
        let totalFrames = frameCount
        let startFrame = max(0, totalFrames - Self.maxGifFrames)
        let count = totalFrames - startFrame
        let interval = frameInterval

        isGenerating = true
        generationProgress = 0

        // GIF生成をバックグラウンドで実行
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Self.generateGifFromDisk(to: url, tempDir: tempDir, startFrame: startFrame, frameCount: count, frameInterval: interval) { progress in
                    Task { @MainActor [weak self] in
                        self?.generationProgress = progress
                    }
                }
                continuation.resume(returning: result)
            }
        }

        isGenerating = false

        cleanupTempDirectory()
        return success ? url : nil
    }

    func cancelRecording() {
        timer?.cancel()
        timer = nil
        isRecording = false
        cleanupTempDirectory()
    }

    private func captureFrame() async {
        guard isRecording, let tempDir = tempDirectory else { return }

        do {
            guard let screen = NSScreen.screenContaining(cgRect: region) else { return }
            let fullImage = try await captureService.captureScreen(screen)

            let scale = CGFloat(fullImage.width) / screen.frame.width

            let screenCGFrame = screen.cgFrame
            let scaledRect = CGRect(
                x: (region.origin.x - screenCGFrame.origin.x) * scale,
                y: (region.origin.y - screenCGFrame.origin.y) * scale,
                width: region.width * scale,
                height: region.height * scale
            )

            let imageRect = CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
            let clampedRect = scaledRect.intersection(imageRect)

            guard !clampedRect.isEmpty, let croppedImage = fullImage.cropping(to: clampedRect) else { return }

            // フレームをディスクに保存
            let frameURL = tempDir.appendingPathComponent(String(format: "frame_%06d.png", frameCount))
            guard let dest = CGImageDestinationCreateWithURL(frameURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, croppedImage, nil)
            if CGImageDestinationFinalize(dest) {
                frameCount += 1
                // 古いフレームを削除して直近maxGifFrames分だけ保持
                let oldIndex = frameCount - Self.maxGifFrames - 1
                if oldIndex >= 0 {
                    let oldURL = tempDir.appendingPathComponent(String(format: "frame_%06d.png", oldIndex))
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }
        } catch {
            print("GIF frame capture error: \(error)")
        }
    }

    // GIFの最大フレーム数（到達で自動停止）
    static let maxGifFrames = 1500

    private nonisolated static func generateGifFromDisk(to url: URL, tempDir: URL, startFrame: Int, frameCount: Int, frameInterval: Double, onProgress: @Sendable @escaping (Double) -> Void) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            print("Failed to create GIF destination")
            return false
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameInterval
            ]
        ]

        for i in 0..<frameCount {
            autoreleasepool {
                let frameURL = tempDir.appendingPathComponent(String(format: "frame_%06d.png", startFrame + i))
                guard let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil) else { return }
                CGImageDestinationAddImageFromSource(destination, source, 0, frameProperties as CFDictionary)
            }
            if i % 50 == 0 {
                onProgress(Double(i) / Double(frameCount) * 0.9)
            }
        }
        onProgress(0.9)

        let success = CGImageDestinationFinalize(destination)
        onProgress(1.0)
        if !success {
            print("Failed to finalize GIF")
        }
        return success
    }

    private func cleanupTempDirectory() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDirectory = nil
        frameCount = 0
    }

    private func generateOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Mas-GIF-\(timestamp).gif"

        if UserDefaults.standard.bool(forKey: "autoSaveEnabled"),
           let folder = UserDefaults.standard.string(forKey: "autoSaveFolder") {
            let folderURL = URL(fileURLWithPath: folder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                return folderURL.appendingPathComponent(fileName)
            }
        }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent(fileName)
    }
}
