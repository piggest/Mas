import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
class VideoPlayerState: ObservableObject {
    let player: AVPlayer
    let duration: Double
    let url: URL
    let fps: Double
    let totalFrames: Int

    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 1.0
    @Published var isScrubbing: Bool = false
    @Published var isTrimming: Bool = false
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var isExporting: Bool = false
    @Published var isExportingGif: Bool = false
    @Published var gifExportProgress: Double = 0
    @Published var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }
    @Published var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }

    private var wasPlayingBeforeScrub = false

    var currentFrame: Int {
        Int(currentTime * fps)
    }

    private var timeObserver: Any?

    init?(url: URL) {
        self.url = url
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        let durationTime = asset.duration
        guard durationTime.isValid, !durationTime.isIndefinite else { return nil }
        self.duration = CMTimeGetSeconds(durationTime)
        guard self.duration > 0 else { return nil }

        // fps取得
        if let track = asset.tracks(withMediaType: .video).first {
            self.fps = Double(track.nominalFrameRate)
        } else {
            self.fps = 20
        }
        self.totalFrames = Int(self.duration * self.fps)

        // 時間監視（0.05秒間隔）
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = CMTimeGetSeconds(time)
            }
        }

        // 再生終了→ループ
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player.seek(to: .zero)
                self.player.play()
            }
        }
    }

    func play() {
        player.rate = Float(speed)
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func beginScrubbing() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        player.pause()
    }

    func endScrubbing() {
        isScrubbing = false
        if wasPlayingBeforeScrub {
            play()
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func nextFrame() {
        pause()
        let frameDuration = 1.0 / fps
        let target = min(currentTime + frameDuration, duration)
        seek(to: target)
    }

    func prevFrame() {
        pause()
        let frameDuration = 1.0 / fps
        let target = max(currentTime - frameDuration, 0)
        seek(to: target)
    }

    func skipForward(_ seconds: Double = 5) {
        let target = min(currentTime + seconds, duration)
        seek(to: target)
    }

    func skipBackward(_ seconds: Double = 5) {
        let target = max(currentTime - seconds, 0)
        seek(to: target)
    }

    func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        if isPlaying {
            player.rate = Float(newSpeed)
        }
    }

    func enterTrimMode() {
        pause()
        isTrimming = true
        trimStart = 0
        trimEnd = duration
    }

    func exitTrimMode() {
        isTrimming = false
    }

    func setTrimStart() {
        trimStart = max(0, min(currentTime, trimEnd - (1.0 / fps)))
    }

    func setTrimEnd() {
        trimEnd = min(duration, max(currentTime, trimStart + (1.0 / fps)))
    }

    var trimDuration: Double {
        trimEnd - trimStart
    }

    func exportTrimmed() async -> URL? {
        isExporting = true
        defer { Task { @MainActor in self.isExporting = false } }

        let asset = AVAsset(url: url)
        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "Mas-Video-Trimmed-\(timestamp).\(ext)"

        let saveFolder: URL
        let autoSaveFolder = UserDefaults.standard.string(forKey: "autoSaveFolder") ?? ""
        if !autoSaveFolder.isEmpty {
            saveFolder = URL(fileURLWithPath: autoSaveFolder)
        } else {
            saveFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures")
                .appendingPathComponent("Mas")
        }

        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let outputURL = saveFolder.appendingPathComponent(fileName)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = ext == "mov" ? .mov : .mp4
        exportSession.timeRange = timeRange

        await exportSession.export()

        if exportSession.status == .completed {
            return outputURL
        }
        return nil
    }

    /// 動画（またはトリム範囲）をGIFとしてエクスポート
    func exportAsGif() async -> URL? {
        let start = isTrimming ? trimStart : 0
        let end = isTrimming ? trimEnd : duration
        return await exportRangeAsGif(start: start, end: end)
    }

    private func exportRangeAsGif(start: Double, end: Double) async -> URL? {
        isExportingGif = true
        gifExportProgress = 0
        defer { Task { @MainActor in self.isExportingGif = false } }

        let gifFps: Double = 10
        let frameDuration = 1.0 / gifFps
        let rangeDuration = end - start
        let frameCount = max(1, Int(rangeDuration * gifFps))

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)

        // 出力先
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "Mas-GIF-\(timestamp).gif"
        let saveFolder: URL
        let autoSaveFolder = UserDefaults.standard.string(forKey: "autoSaveFolder") ?? ""
        if !autoSaveFolder.isEmpty {
            saveFolder = URL(fileURLWithPath: autoSaveFolder)
        } else {
            saveFolder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures")
                .appendingPathComponent("Mas")
        }
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let outputURL = saveFolder.appendingPathComponent(fileName)

        // フレーム抽出とGIF生成をバックグラウンドで
        let srcURL = url
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let destination = CGImageDestinationCreateWithURL(
                    outputURL as CFURL,
                    UTType.gif.identifier as CFString,
                    frameCount,
                    nil
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                let gifProperties: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFLoopCount as String: 0
                    ]
                ]
                CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

                let frameProperties: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: frameDuration
                    ]
                ]

                let bgAsset = AVURLAsset(url: srcURL)
                let bgGenerator = AVAssetImageGenerator(asset: bgAsset)
                bgGenerator.appliesPreferredTrackTransform = true
                bgGenerator.requestedTimeToleranceBefore = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)
                bgGenerator.requestedTimeToleranceAfter = CMTime(seconds: frameDuration / 2, preferredTimescale: 600)

                for i in 0..<frameCount {
                    let time = CMTime(seconds: start + Double(i) * frameDuration, preferredTimescale: 600)
                    guard let cgImage = try? bgGenerator.copyCGImage(at: time, actualTime: nil) else { continue }
                    CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)

                    if i % 10 == 0 {
                        let progress = Double(i) / Double(frameCount)
                        Task { @MainActor in
                            self.gifExportProgress = progress
                        }
                    }
                }

                let success = CGImageDestinationFinalize(destination)
                Task { @MainActor in
                    self.gifExportProgress = 1.0
                }
                continuation.resume(returning: success ? outputURL : nil)
            }
        }

        return result
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        player.pause()
    }
}
