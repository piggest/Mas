import AppKit
import ImageIO

@MainActor
class GifPlayerState: ObservableObject {
    var frames: [NSImage]
    let frameDelays: [Double]

    @Published var currentFrameIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var speed: Double = 1.0

    private var timer: Timer?

    var frameCount: Int { frames.count }

    var currentFrameImage: NSImage {
        guard currentFrameIndex < frames.count else {
            return frames.first ?? NSImage()
        }
        return frames[currentFrameIndex]
    }

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        var loadedFrames: [NSImage] = []
        var delays: [Double] = []

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            // Retina対応: ポイントサイズに変換
            let pointSize = NSSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
            let nsImage = NSImage(cgImage: cgImage, size: pointSize)
            loadedFrames.append(nsImage)

            // フレームのdelay取得
            var delay: Double = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                if let unclampedDelay = gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, unclampedDelay > 0 {
                    delay = unclampedDelay
                } else if let clampedDelay = gifDict[kCGImagePropertyGIFDelayTime as String] as? Double, clampedDelay > 0 {
                    delay = clampedDelay
                }
            }
            delays.append(delay)
        }

        guard !loadedFrames.isEmpty else { return nil }

        self.frames = loadedFrames
        self.frameDelays = delays
    }

    func play() {
        guard !isPlaying, frameCount > 1 else { return }
        isPlaying = true
        scheduleNextFrame()
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seekTo(frame: Int) {
        let wasPlaying = isPlaying
        pause()
        currentFrameIndex = max(0, min(frame, frameCount - 1))
        if wasPlaying {
            play()
        }
    }

    func nextFrame() {
        pause()
        currentFrameIndex = (currentFrameIndex + 1) % frameCount
    }

    func prevFrame() {
        pause()
        currentFrameIndex = (currentFrameIndex - 1 + frameCount) % frameCount
    }

    private func scheduleNextFrame() {
        guard isPlaying else { return }

        let delay = frameDelays[currentFrameIndex] / speed
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isPlaying else { return }
                self.currentFrameIndex = (self.currentFrameIndex + 1) % self.frameCount
                self.scheduleNextFrame()
            }
        }
    }

    func replaceFrames(_ newFrames: [NSImage]) {
        guard newFrames.count == frames.count else { return }
        frames = newFrames
        objectWillChange.send()
    }

    deinit {
        timer?.invalidate()
    }
}
