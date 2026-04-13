import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

@MainActor
class VideoRecordingService {
    private var frameCount: Int = 0
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: DispatchSourceTimer?
    private var region: CGRect = .zero
    private(set) var isRecording = false
    private var startTime: Date?
    private let captureService = ScreenCaptureService()
    private let fps: Double = 20
    private var outputURL: URL?

    // システムオーディオ録音
    private var audioInput: AVAssetWriterInput?
    private var scStream: SCStream?
    private var audioDelegate: AudioStreamDelegate?
    var audioEnabled: Bool = false

    var elapsedTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    func startRecording(region: CGRect) {
        self.region = region
        self.frameCount = 0
        self.startTime = Date()

        let url = generateOutputURL()
        self.outputURL = url

        guard let screen = NSScreen.screenContaining(cgRect: region) else { return }
        let scale = screen.backingScaleFactor
        // ピクセル数を偶数に揃える（H.264要件）
        let pixelWidth = Int(region.width * scale) & ~1
        let pixelHeight = Int(region.height * scale) & ~1

        guard pixelWidth > 0, pixelHeight > 0 else { return }

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: pixelWidth,
                AVVideoHeightKey: pixelHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: pixelWidth * pixelHeight * 4,
                    AVVideoMaxKeyFrameIntervalKey: Int(fps),
                ]
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight,
            ]

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            writer.add(input)

            // オーディオ入力の設定
            if audioEnabled {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128000,
                ]
                let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioWriterInput.expectsMediaDataInRealTime = true
                writer.add(audioWriterInput)
                self.audioInput = audioWriterInput
            }

            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            self.assetWriter = writer
            self.videoInput = input
            self.pixelBufferAdaptor = adaptor
        } catch {
            print("AVAssetWriterの作成に失敗: \(error)")
            return
        }

        self.isRecording = true

        let frameInterval = 1.0 / fps
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: frameInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.captureFrame()
            }
        }
        self.timer = timer
        timer.resume()

        // システムオーディオキャプチャ開始
        if audioEnabled {
            Task {
                await startSystemAudioCapture()
            }
        }
    }

    private func startSystemAudioCapture() async {
        guard let audioInput = self.audioInput else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                print("ディスプレイが見つからない")
                return
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            // 映像は不要（映像は既存のCGWindowList方式で取得）
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.sampleRate = 48000
            config.channelCount = 2

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            let delegate = AudioStreamDelegate(audioInput: audioInput, startTime: startTime ?? Date())
            self.audioDelegate = delegate

            try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream.startCapture()
            self.scStream = stream
        } catch {
            print("システムオーディオキャプチャの開始に失敗: \(error)")
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        timer?.cancel()
        timer = nil
        isRecording = false

        // システムオーディオキャプチャ停止
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        audioDelegate = nil

        guard let writer = assetWriter, let input = videoInput else {
            return nil
        }

        input.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil

        if writer.status == .completed {
            return url
        } else {
            print("動画の書き出しに失敗: \(writer.error?.localizedDescription ?? "不明")")
            if let url = url {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }
    }

    func cancelRecording() {
        timer?.cancel()
        timer = nil
        isRecording = false

        if let stream = scStream {
            Task { try? await stream.stopCapture() }
            scStream = nil
        }
        audioDelegate = nil

        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
    }

    private func captureFrame() async {
        guard isRecording,
              let input = videoInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData else { return }

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

            let presentationTime = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(fps))

            guard let pixelBuffer = createPixelBuffer(from: croppedImage) else { return }

            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            frameCount += 1
        } catch {
            print("動画フレームキャプチャエラー: \(error)")
        }
    }

    private func createPixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    private func generateOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Mas-Video-\(timestamp).mp4"

        if UserDefaults.standard.bool(forKey: "autoSaveEnabled"),
           let folder = UserDefaults.standard.string(forKey: "autoSaveFolder"),
           !folder.isEmpty {
            let folderURL = URL(fileURLWithPath: folder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                return folderURL.appendingPathComponent(fileName)
            }
        }

        // デフォルトはピクチャフォルダ内のMasフォルダ
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let masFolder = picturesURL.appendingPathComponent("Mas")
        try? FileManager.default.createDirectory(at: masFolder, withIntermediateDirectories: true)
        return masFolder.appendingPathComponent(fileName)
    }
}

// ScreenCaptureKitのオーディオサンプルを受け取るデリゲート
class AudioStreamDelegate: NSObject, SCStreamOutput {
    private let audioInput: AVAssetWriterInput
    private let startTime: Date

    init(audioInput: AVAssetWriterInput, startTime: Date) {
        self.audioInput = audioInput
        self.startTime = startTime
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              audioInput.isReadyForMoreMediaData,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // タイムスタンプを録画開始時刻基準に補正
        let elapsed = Date().timeIntervalSince(startTime)
        let newTime = CMTime(seconds: elapsed, preferredTimescale: 48000)

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newTime,
            decodeTimeStamp: .invalid
        )

        var adjustedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedBuffer
        )

        if let buffer = adjustedBuffer {
            audioInput.append(buffer)
        }
    }
}
