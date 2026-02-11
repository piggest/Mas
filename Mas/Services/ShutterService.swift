import AppKit
import CoreGraphics

enum ShutterMode: String {
    case delayed = "delayed"
    case interval = "interval"
    case changeDetection = "changeDetection"
}

@MainActor
class ShutterService: ObservableObject {
    @Published var isActive = false
    @Published var activeMode: ShutterMode? = nil
    @Published var countdown: Int = 0
    @Published var captureCount: Int = 0
    @Published var maxCaptureCount: Int = 0
    @Published var sensitivity: Double = 0.05

    var onCapture: (() -> Void)?
    private var timer: DispatchSourceTimer?
    private var monitorTimer: DispatchSourceTimer?
    private var referenceImage: CGImage?
    private let captureService = ScreenCaptureService()

    // MARK: - Delayed Capture

    func startDelayed(seconds: Int) {
        stopAll()
        activeMode = .delayed
        isActive = true
        countdown = seconds

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.countdown -= 1
                if self.countdown <= 0 {
                    self.onCapture?()
                    self.stopAll()
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    // MARK: - Interval Capture

    func startInterval(seconds: Double, maxCount: Int = 0) {
        stopAll()
        activeMode = .interval
        isActive = true
        captureCount = 0
        maxCaptureCount = maxCount

        // 開始時に即1枚キャプチャ
        captureCount += 1
        onCapture?()

        // maxCount == 1 の場合は即停止
        if maxCaptureCount > 0 && captureCount >= maxCaptureCount {
            stopAll()
            return
        }

        let intervalMs = Int(seconds * 1000)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.captureCount += 1
                self.onCapture?()
                if self.maxCaptureCount > 0 && self.captureCount >= self.maxCaptureCount {
                    self.stopAll()
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    // MARK: - Change Detection

    private var regionProvider: (() -> CGRect)?

    func startChangeDetection(regionProvider: @escaping () -> CGRect) {
        stopAll()
        activeMode = .changeDetection
        isActive = true
        captureCount = 0
        self.regionProvider = regionProvider

        // 開始時に即1枚キャプチャ
        onCapture?()
        captureCount += 1

        // Capture initial reference image
        Task {
            let region = regionProvider()
            guard region.width > 0, region.height > 0 else {
                print("[ShutterService] Invalid region: \(region)")
                stopAll()
                return
            }
            if let image = await captureRegionImage(region) {
                self.referenceImage = image
            } else {
                print("[ShutterService] Failed to capture reference image for region: \(region)")
                stopAll()
                return
            }

            let monitorTimer = DispatchSource.makeTimerSource(queue: .main)
            monitorTimer.schedule(deadline: .now() + 0.5, repeating: 0.5)
            monitorTimer.setEventHandler { [weak self] in
                Task { @MainActor in
                    await self?.checkForChanges()
                }
            }
            self.monitorTimer = monitorTimer
            monitorTimer.resume()
        }
    }

    // MARK: - Stop

    func stopAll() {
        timer?.cancel()
        timer = nil
        monitorTimer?.cancel()
        monitorTimer = nil
        referenceImage = nil
        regionProvider = nil
        isActive = false
        activeMode = nil
        countdown = 0
    }

    // MARK: - Private

    private func captureRegionImage(_ region: CGRect) async -> CGImage? {
        guard let screen = NSScreen.screenContaining(cgRect: region) else { return nil }
        do {
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
            guard !clampedRect.isEmpty else { return nil }
            return fullImage.cropping(to: clampedRect)
        } catch {
            return nil
        }
    }

    private func checkForChanges() async {
        guard isActive, activeMode == .changeDetection else { return }
        guard let reference = referenceImage else { return }
        guard let provider = regionProvider else { return }

        let region = provider()
        guard region.width > 0, region.height > 0 else { return }
        guard let current = await captureRegionImage(region) else { return }

        let diff = imageDifference(reference, current)
        if diff > sensitivity {
            captureCount += 1
            referenceImage = current
            onCapture?()
        }
    }

    private func imageDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let size = 100
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        let totalBytes = size * bytesPerRow

        guard let contextA = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let contextB = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        contextA.draw(a, in: rect)
        contextB.draw(b, in: rect)

        guard let dataA = contextA.data, let dataB = contextB.data else { return 0 }

        let bufferA = dataA.bindMemory(to: UInt8.self, capacity: totalBytes)
        let bufferB = dataB.bindMemory(to: UInt8.self, capacity: totalBytes)

        var totalDiff: Int = 0
        for i in 0..<totalBytes {
            totalDiff += abs(Int(bufferA[i]) - Int(bufferB[i]))
        }

        let maxDiff = totalBytes * 255
        return Double(totalDiff) / Double(maxDiff)
    }
}
