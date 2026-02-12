import AppKit
import CoreGraphics

// MARK: - Programmable Step Model

enum ProgramStepType: String, CaseIterable {
    case capture = "撮影"
    case wait = "待機"
    case waitForChange = "変化待ち"
    case loop = "繰り返し"
}

struct ProgramStep: Identifiable {
    let id = UUID()
    var type: ProgramStepType
    var waitSeconds: Double = 3.0
    var sensitivity: Double = 0.05
    var loopCount: Int = 0
    var children: [ProgramStep] = []  // .loop専用
}

enum ShutterMode: String {
    case delayed = "delayed"
    case interval = "interval"
    case changeDetection = "changeDetection"
    case programmable = "programmable"
}

@MainActor
class ShutterService: ObservableObject {
    @Published var isActive = false
    @Published var activeMode: ShutterMode? = nil
    @Published var countdown: Int = 0
    @Published var captureCount: Int = 0
    @Published var maxCaptureCount: Int = 0
    @Published var sensitivity: Double = 0.05
    @Published var currentDiff: Double = 0
    @Published var monitorSubRect: CGRect?  // 正規化座標(0〜1)のサブ領域。nilなら全体監視
    @Published var currentStepId: UUID? = nil

    var onCapture: (() -> Void)?
    private var timer: DispatchSourceTimer?
    private var monitorTimer: DispatchSourceTimer?
    private var referenceImage: CGImage?
    private let captureService = ScreenCaptureService()
    private var programmableTask: Task<Void, Never>?

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
            let fullRegion = regionProvider()
            let region = self.monitorRegion(from: fullRegion)
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

    // MARK: - Programmable Capture

    func startProgrammable(steps: [ProgramStep], regionProvider: @escaping () -> CGRect) {
        stopAll()
        activeMode = .programmable
        isActive = true
        captureCount = 0
        self.regionProvider = regionProvider

        programmableTask = Task { [weak self] in
            await self?.executeProgrammableSteps(steps: steps)
        }
    }

    private func executeProgrammableSteps(steps: [ProgramStep]) async {
        guard !steps.isEmpty else {
            stopAll()
            return
        }

        await executeSteps(steps)

        if !Task.isCancelled {
            await MainActor.run {
                self.currentStepId = nil
                self.isActive = false
                self.activeMode = nil
            }
        }
    }

    /// 再帰的にステップリストを実行する
    private func executeSteps(_ steps: [ProgramStep]) async {
        for step in steps {
            guard !Task.isCancelled else { return }
            currentStepId = step.id

            switch step.type {
            case .capture:
                captureCount += 1
                onCapture?()

            case .wait:
                let nanoseconds = UInt64(step.waitSeconds * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return  // cancelled
                }

            case .waitForChange:
                guard let provider = regionProvider else { break }
                let fullRegion = provider()
                let region = monitorRegion(from: fullRegion)
                guard region.width > 0, region.height > 0 else { break }
                guard let refImage = await captureRegionImage(region) else { break }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5秒
                    } catch {
                        return
                    }
                    let currentRegion = monitorRegion(from: provider())
                    guard let current = await captureRegionImage(currentRegion) else { continue }
                    let diff = imageDifference(refImage, current)
                    currentDiff = diff
                    if diff > step.sensitivity {
                        break
                    }
                }

            case .loop:
                let iterations = step.loopCount  // 0 = 無限
                if iterations == 0 {
                    while !Task.isCancelled {
                        await executeSteps(step.children)
                    }
                } else {
                    for _ in 0..<iterations {
                        guard !Task.isCancelled else { return }
                        await executeSteps(step.children)
                    }
                }
            }
        }
    }

    // MARK: - Stop

    func stopAll() {
        programmableTask?.cancel()
        programmableTask = nil
        currentStepId = nil
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

    /// 正規化座標のサブ領域を絶対CG座標に変換。monitorSubRect が nil なら fullRegion をそのまま返す
    private func monitorRegion(from fullRegion: CGRect) -> CGRect {
        guard let sub = monitorSubRect else { return fullRegion }
        return CGRect(
            x: fullRegion.origin.x + fullRegion.width * sub.origin.x,
            y: fullRegion.origin.y + fullRegion.height * sub.origin.y,
            width: fullRegion.width * sub.width,
            height: fullRegion.height * sub.height
        )
    }

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

        let fullRegion = provider()
        let region = monitorRegion(from: fullRegion)
        guard region.width > 0, region.height > 0 else { return }
        guard let current = await captureRegionImage(region) else { return }

        let diff = imageDifference(reference, current)
        currentDiff = diff
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
