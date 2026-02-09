import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
class GifRecordingService {
    private var frames: [CGImage] = []
    private var timer: DispatchSourceTimer?
    private var region: CGRect = .zero
    private(set) var isRecording = false
    private var startTime: Date?
    private let captureService = ScreenCaptureService()
    private let frameInterval: Double = 0.1  // 10fps

    var elapsedTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    func startRecording(region: CGRect) {
        self.region = region
        self.frames = []
        self.isRecording = true
        self.startTime = Date()

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

        guard !frames.isEmpty else { return nil }

        // 保存先URLを生成
        let url = generateOutputURL()

        // GIF生成
        let success = generateGif(to: url)
        frames = []

        return success ? url : nil
    }

    func cancelRecording() {
        timer?.cancel()
        timer = nil
        isRecording = false
        frames = []
    }

    private func captureFrame() async {
        guard isRecording else { return }

        do {
            // regionが属するスクリーンを特定してキャプチャ
            guard let screen = NSScreen.screenContaining(cgRect: region) else { return }
            let fullImage = try await captureService.captureScreen(screen)

            let scale = CGFloat(fullImage.width) / screen.frame.width

            // CGグローバル座標をスクリーン相対座標に変換
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

            frames.append(croppedImage)
        } catch {
            print("GIF frame capture error: \(error)")
        }
    }

    private func generateGif(to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            print("Failed to create GIF destination")
            return false
        }

        // GIFファイルプロパティ（無限ループ）
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // 各フレーム追加
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameInterval
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        let success = CGImageDestinationFinalize(destination)
        if !success {
            print("Failed to finalize GIF")
        }
        return success
    }

    private func generateOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Mas-GIF-\(timestamp).gif"

        // 自動保存フォルダがあればそちらに保存
        if UserDefaults.standard.bool(forKey: "autoSaveEnabled"),
           let folder = UserDefaults.standard.string(forKey: "autoSaveFolder") {
            let folderURL = URL(fileURLWithPath: folder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                return folderURL.appendingPathComponent(fileName)
            }
        }

        // デフォルトはデスクトップ
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent(fileName)
    }
}
