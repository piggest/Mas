import AppKit
import CoreGraphics

// MARK: - Programmable Step Model

enum ProgramStepType: String, CaseIterable, Codable {
    case capture = "撮影"
    case wait = "待機"
    case waitForChange = "変化待ち"
    case waitForStable = "安定待ち"
    case loop = "繰り返し"
}

struct ProgramStep: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: ProgramStepType
    var waitSeconds: Double = 3.0
    var sensitivity: Double = 0.05
    var loopCount: Int = 0
    var children: [ProgramStep] = []  // .loop専用
    var monitorSubRect: CGRect? = nil  // .waitForChange専用: 正規化座標(0〜1)
}

// MARK: - Program Persistence

struct ProgramStepStore {
    private static let lastStepsKey = "programmableShutter.lastSteps"
    private static let savedProgramsKey = "programmableShutter.savedPrograms"

    static func saveLastSteps(_ steps: [ProgramStep]) {
        guard let data = try? JSONEncoder().encode(steps) else { return }
        UserDefaults.standard.set(data, forKey: lastStepsKey)
    }

    static func loadLastSteps() -> [ProgramStep] {
        guard let data = UserDefaults.standard.data(forKey: lastStepsKey),
              let steps = try? JSONDecoder().decode([ProgramStep].self, from: data) else { return [] }
        return steps
    }

    static func saveProgram(name: String, steps: [ProgramStep]) {
        var programs = loadAllPrograms()
        programs[name] = steps
        guard let data = try? JSONEncoder().encode(programs) else { return }
        UserDefaults.standard.set(data, forKey: savedProgramsKey)
    }

    static func loadAllPrograms() -> [String: [ProgramStep]] {
        guard let data = UserDefaults.standard.data(forKey: savedProgramsKey),
              let programs = try? JSONDecoder().decode([String: [ProgramStep]].self, from: data) else { return [:] }
        return programs
    }

    static func deleteProgram(name: String) {
        var programs = loadAllPrograms()
        programs.removeValue(forKey: name)
        guard let data = try? JSONEncoder().encode(programs) else { return }
        UserDefaults.standard.set(data, forKey: savedProgramsKey)
    }
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
    private var lastCapturedImage: CGImage?  // プログラマブル: 前回の撮影ステップの画像
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
                // 撮影直後の画面をサブ領域ごとにキャプチャして保存（変化待ち・安定待ちの基準）
                if let provider = regionProvider {
                    lastCapturedImage = await captureRegionImage(provider())
                }

            case .wait:
                let nanoseconds = UInt64(step.waitSeconds * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return  // cancelled
                }

            case .waitForChange:
                guard let provider = regionProvider else { break }
                let region = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                guard region.width > 0, region.height > 0 else { break }
                // 前回撮影の同一領域をキャプチャして基準とする（なければ今の画面）
                let refImage: CGImage
                if let lastFull = lastCapturedImage {
                    // 前回撮影時のフル画像から、同じ方法でサブ領域をキャプチャし直す
                    let refRegion = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                    refImage = await captureRefFromLastCapture(fullImage: lastFull, fullRegion: provider(), subRegion: refRegion)
                } else {
                    guard let fallback = await captureRegionImage(region) else { break }
                    refImage = fallback
                }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        return
                    }
                    let currentRegion = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                    guard let current = await captureRegionImage(currentRegion) else { continue }
                    let diff = imageDifference(refImage, current)
                    currentDiff = diff
                    if diff > step.sensitivity {
                        break
                    }
                }

            case .waitForStable:
                guard let provider = regionProvider else { break }
                let stableRegion = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                guard stableRegion.width > 0, stableRegion.height > 0 else { break }
                // 前回撮影の同一領域を基準に、変化率がしきい値以下になるまで待つ
                let stableRef: CGImage
                if let lastFull = lastCapturedImage {
                    let refRegion = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                    stableRef = await captureRefFromLastCapture(fullImage: lastFull, fullRegion: provider(), subRegion: refRegion)
                } else {
                    guard let fallback = await captureRegionImage(stableRegion) else { break }
                    stableRef = fallback
                }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    } catch {
                        return
                    }
                    let curRegion = stepMonitorRegion(from: provider(), subRect: step.monitorSubRect)
                    guard let curImage = await captureRegionImage(curRegion) else { continue }
                    let diff = imageDifference(stableRef, curImage)
                    currentDiff = diff
                    if diff <= step.sensitivity {
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
        lastCapturedImage = nil
        regionProvider = nil
        isActive = false
        activeMode = nil
        countdown = 0
    }

    // MARK: - Private

    /// ステップ固有の正規化サブ領域を絶対CG座標に変換。subRect が nil ならフル領域を返す
    private func stepMonitorRegion(from fullRegion: CGRect, subRect: CGRect?) -> CGRect {
        guard let sub = subRect else { return fullRegion }
        return CGRect(
            x: fullRegion.origin.x + fullRegion.width * sub.origin.x,
            y: fullRegion.origin.y + fullRegion.height * sub.origin.y,
            width: fullRegion.width * sub.width,
            height: fullRegion.height * sub.height
        )
    }

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

    /// lastCapturedImage（フル領域）からサブ領域を切り出す。
    /// fullRegion と subRegion の比率でフル画像をクロップする。
    private func captureRefFromLastCapture(fullImage: CGImage, fullRegion: CGRect, subRegion: CGRect) -> CGImage {
        // サブ領域がフル領域と同じならそのまま返す
        guard fullRegion.width > 0, fullRegion.height > 0 else { return fullImage }
        let relX = (subRegion.origin.x - fullRegion.origin.x) / fullRegion.width
        let relY = (subRegion.origin.y - fullRegion.origin.y) / fullRegion.height
        let relW = subRegion.width / fullRegion.width
        let relH = subRegion.height / fullRegion.height

        // ほぼ全体ならクロップ不要
        if relX <= 0.001 && relY <= 0.001 && relW >= 0.999 && relH >= 0.999 {
            return fullImage
        }

        let cropRect = CGRect(
            x: CGFloat(fullImage.width) * relX,
            y: CGFloat(fullImage.height) * relY,
            width: CGFloat(fullImage.width) * relW,
            height: CGFloat(fullImage.height) * relH
        ).integral  // ピクセル境界に揃える

        let imageRect = CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
        let clamped = cropRect.intersection(imageRect)
        guard !clamped.isEmpty else { return fullImage }
        return fullImage.cropping(to: clamped) ?? fullImage
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
