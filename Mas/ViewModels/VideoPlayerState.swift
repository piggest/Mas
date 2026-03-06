import AppKit
import AVFoundation

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

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        player.pause()
    }
}
