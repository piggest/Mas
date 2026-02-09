import SwiftUI
import UniformTypeIdentifiers

@MainActor
class CaptureViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var isRecording = false
    @Published var currentScreenshot: Screenshot?
    @Published var errorMessage: String?

    private let captureService = ScreenCaptureService()
    private let clipboardService = ClipboardService()
    private let fileStorageService = FileStorageService()
    private let permissionService = PermissionService()
    private let captureFlash = CaptureFlashView()
    private let historyService = HistoryService()
    private var gifRecordingService: GifRecordingService?
    private var recordingControlWindow: RecordingControlWindowController?
    private var gifRecordingRegion: CGRect?

    @Published var historyEntries: [ScreenshotHistoryEntry] = []

    // エディターウィンドウ情報（メニュー表示用）
    struct EditorWindowInfo: Identifiable {
        let id: UUID
        let windowController: NSWindowController
        let screenshot: Screenshot
        let toolboxState: ToolboxState
        let createdAt: Date

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeStr = formatter.string(from: createdAt)
            return "\(screenshot.mode.rawValue) - \(timeStr)"
        }
    }

    @Published private(set) var editorWindows: [EditorWindowInfo] = []

    // 前回のキャプチャ範囲を保存するキー
    private let lastCaptureRectKey = "lastCaptureRect"

    private var historyWindowController: NSWindowController?
    private var historyWindowDelegate: HistoryWindowDelegateHandler?

    init() {
        historyEntries = historyService.load()
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureFullScreen),
            name: .captureFullScreen,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureRegion),
            name: .captureRegion,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowCaptureFrame),
            name: .showCaptureFrame,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEditorWindowClosed),
            name: .editorWindowClosed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartGifRecording),
            name: .startGifRecording,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartGifRecordingAtRegion(_:)),
            name: .startGifRecordingAtRegion,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowHistory),
            name: .showHistory,
            object: nil
        )
    }

    @objc private func handleShowHistory() {
        showHistoryWindow()
    }

    @objc private func handleEditorWindowClosed() {
        cleanupClosedWindows()
    }

    @objc private func handleCaptureFullScreen() {
        Task { await captureFullScreen() }
    }

    @objc private func handleCaptureRegion() {
        Task { await startRegionSelection() }
    }

    @objc private func handleShowCaptureFrame() {
        Task { await showCaptureFrame() }
    }

    @objc private func handleStartGifRecording() {
        Task { await startGifRecording() }
    }

    @objc private func handleStartGifRecordingAtRegion(_ notification: Notification) {
        guard let rect = notification.object as? NSValue else { return }
        let region = rect.rectValue
        Task { await beginRecordingFromWindow(in: region) }
    }

    // 前回のキャプチャ範囲を保存
    private func saveLastCaptureRect(_ rect: CGRect) {
        let rectDict: [String: CGFloat] = [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.width,
            "height": rect.height
        ]
        UserDefaults.standard.set(rectDict, forKey: lastCaptureRectKey)
    }

    // 前回のキャプチャ範囲を読み込み
    private func loadLastCaptureRect() -> CGRect? {
        guard let rectDict = UserDefaults.standard.dictionary(forKey: lastCaptureRectKey) as? [String: CGFloat],
              let x = rectDict["x"],
              let y = rectDict["y"],
              let width = rectDict["width"],
              let height = rectDict["height"] else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // デフォルトのキャプチャ範囲（画面中央、幅1/3）CGグローバル座標
    private func defaultCaptureRect() -> CGRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return CGRect(x: 100, y: 100, width: 400, height: 300)
        }
        let cgFrame = screen.cgFrame
        let frameWidth = cgFrame.width / 3
        let frameHeight = frameWidth * 0.75 // 4:3のアスペクト比
        let x = cgFrame.origin.x + (cgFrame.width - frameWidth) / 2
        let y = cgFrame.origin.y + (cgFrame.height - frameHeight) / 2
        return CGRect(x: x, y: y, width: frameWidth, height: frameHeight)
    }

    private func checkPermission() async -> Bool {
        guard permissionService.hasScreenCapturePermission() else {
            await permissionService.requestScreenCapturePermission()
            return false
        }
        return true
    }

    func captureFullScreen() async {
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        // キャプチャ中はライブラリウィンドウを一時非表示
        let libraryWasVisible = historyWindowController?.window?.isVisible == true
        if libraryWasVisible {
            historyWindowController?.window?.orderOut(nil)
        }

        do {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                errorMessage = "ディスプレイが見つかりません"
                isCapturing = false
                return
            }

            let cgImage = try await captureService.captureScreen(screen)

            // 画面全体をCGグローバル座標でregionとして設定
            let fullScreenRect = screen.cgFrame

            let screenshot = Screenshot(cgImage: cgImage, mode: .fullScreen, region: fullScreenRect)
            currentScreenshot = screenshot
            captureFlash.showFlash(in: fullScreenRect)
            processScreenshot(screenshot)
            showEditorWindow(for: screenshot, at: fullScreenRect)
        } catch {
            errorMessage = error.localizedDescription
            print("Capture error: \(error)")
        }

        // ライブラリウィンドウを復元
        if libraryWasVisible {
            historyWindowController?.window?.orderBack(nil)
        }

        isCapturing = false
    }

    func startRegionSelection() async {
        guard !isCapturing else { return }
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        // キャプチャ中はライブラリウィンドウを一時非表示
        let libraryWasVisible = historyWindowController?.window?.isVisible == true
        if libraryWasVisible {
            historyWindowController?.window?.orderOut(nil)
        }

        do {
            // 先に全スクリーンをキャプチャしておく（マルチスクリーン対応）
            let screenImages = try await captureService.captureAllScreens()

            let overlay = RegionSelectionOverlay(onComplete: { [weak self] rect in
                guard let self = self else { return }
                // キャプチャ完了後にライブラリウィンドウを復元
                if libraryWasVisible {
                    self.historyWindowController?.window?.orderBack(nil)
                }
                Task {
                    await self.cropRegion(rect, from: screenImages)
                }
            }, onCancel: { [weak self] in
                self?.isCapturing = false
                // キャンセル時もライブラリウィンドウを復元
                if libraryWasVisible {
                    self?.historyWindowController?.window?.orderBack(nil)
                }
            })
            overlay.show()
        } catch {
            errorMessage = error.localizedDescription
            print("Capture error: \(error)")
            isCapturing = false
        }
    }

    private func cropRegion(_ rect: CGRect, from screenImages: [CGDirectDisplayID: CGImage]) async {
        // 選択領域が属するスクリーンを特定
        guard let screen = NSScreen.screenContaining(cgRect: rect),
              let displayID = screen.displayID,
              let fullImage = screenImages[displayID] else {
            errorMessage = "ディスプレイが見つかりません"
            isCapturing = false
            return
        }

        let imageWidth = CGFloat(fullImage.width)
        let imageHeight = CGFloat(fullImage.height)

        // スケール計算（Retina対応）
        let scale = imageWidth / screen.frame.width

        // CGグローバル座標をスクリーン相対座標に変換してからスケール適用
        let screenCGFrame = screen.cgFrame
        let scaledRect = CGRect(
            x: (rect.origin.x - screenCGFrame.origin.x) * scale,
            y: (rect.origin.y - screenCGFrame.origin.y) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        // 範囲チェック
        let clampedRect = scaledRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard !clampedRect.isEmpty, let croppedImage = fullImage.cropping(to: clampedRect) else {
            errorMessage = "画像の切り取りに失敗しました"
            isCapturing = false
            return
        }

        // 選択範囲を保存してスクリーンショットを作成
        let screenshot = Screenshot(cgImage: croppedImage, mode: .region, region: rect)
        currentScreenshot = screenshot
        captureFlash.showFlash(in: rect)
        processScreenshot(screenshot)
        showEditorWindow(for: screenshot, at: rect)

        // 前回のキャプチャ範囲を保存
        saveLastCaptureRect(rect)

        isCapturing = false
    }

    // 再キャプチャ機能（現在のウィンドウ位置で）
    func recaptureRegion(for screenshot: Screenshot, at region: CGRect, window: NSWindow?) async {
        // ウィンドウを一時的に隠す
        window?.orderOut(nil)

        // 少し待つ
        try? await Task.sleep(nanoseconds: 200_000_000)

        do {
            // regionが属するスクリーンを特定してキャプチャ
            guard let screen = NSScreen.screenContaining(cgRect: region) else {
                window?.makeKeyAndOrderFront(nil)
                return
            }

            let fullScreenImage = try await captureService.captureScreen(screen)

            let imageWidth = CGFloat(fullScreenImage.width)
            let imageHeight = CGFloat(fullScreenImage.height)
            let scale = imageWidth / screen.frame.width

            // CGグローバル座標をスクリーン相対座標に変換
            let screenCGFrame = screen.cgFrame
            let scaledRect = CGRect(
                x: (region.origin.x - screenCGFrame.origin.x) * scale,
                y: (region.origin.y - screenCGFrame.origin.y) * scale,
                width: region.width * scale,
                height: region.height * scale
            )

            let clampedRect = scaledRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

            guard !clampedRect.isEmpty, let croppedImage = fullScreenImage.cropping(to: clampedRect) else {
                window?.makeKeyAndOrderFront(nil)
                return
            }

            // フラッシュアニメーション
            captureFlash.showFlash(in: region)

            // 画像と範囲を更新
            screenshot.updateImage(croppedImage)
            screenshot.captureRegion = region

            // GIFモードだった場合はスクリーンショットモードに変更
            if screenshot.isGif {
                screenshot.savedURL = nil
            }

            // リサイズ状態をリセット（オフセットをクリア）
            if let resizableWindow = window as? ResizableWindow {
                resizableWindow.resizeState.reset()
            }

            // 新しい画像を保存
            processScreenshot(screenshot)

            // メニューのサムネイル更新を通知
            objectWillChange.send()

            // ウィンドウを再表示
            window?.makeKeyAndOrderFront(nil)
        } catch {
            print("Recapture error: \(error)")
            window?.makeKeyAndOrderFront(nil)
        }
    }

    // キャプチャ枠だけを表示（画像なし）
    func showCaptureFrame() async {
        guard await checkPermission() else { return }

        // 前回のキャプチャ範囲を読み込み、なければデフォルト
        let frameRect = loadLastCaptureRect() ?? defaultCaptureRect()

        // 透明な画像を作成
        let width = Int(frameRect.width)
        let height = Int(frameRect.height)
        guard width > 0, height > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // 完全に透明な画像
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else { return }

        let screenshot = Screenshot(cgImage: cgImage, mode: .region, region: frameRect)
        currentScreenshot = screenshot
        showEditorWindow(for: screenshot, at: frameRect, showImageInitially: false)
    }

    // MARK: - GIF録画

    func startGifRecording() async {
        guard !isCapturing, !isRecording else { return }
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        let overlay = RegionSelectionOverlay(onComplete: { [weak self] rect in
            guard let self = self else { return }
            self.isCapturing = false
            Task {
                await self.beginRecording(in: rect)
            }
        }, onCancel: { [weak self] in
            self?.isCapturing = false
        })
        overlay.show()
    }

    // エディターウィンドウの位置から直接録画開始
    func beginRecordingFromWindow(in region: CGRect) async {
        guard !isRecording else { return }
        await beginRecording(in: region)
    }

    private func beginRecording(in region: CGRect) async {
        let service = GifRecordingService()
        self.gifRecordingService = service
        self.gifRecordingRegion = region

        let controlWindow = RecordingControlWindowController()
        self.recordingControlWindow = controlWindow

        service.startRecording(region: region)
        isRecording = true

        controlWindow.show(above: region) { [weak self] in
            guard let self = self else { return }
            Task {
                await self.stopGifRecording()
            }
        }
    }

    func stopGifRecording() async {
        guard isRecording else { return }

        recordingControlWindow?.close()
        recordingControlWindow = .none

        guard let service = gifRecordingService else {
            isRecording = false
            return
        }

        let gifURL = await service.stopRecording()
        gifRecordingService = .none
        isRecording = false

        guard let url = gifURL, let nsImage = NSImage(contentsOf: url) else {
            errorMessage = "GIFの生成に失敗しました"
            return
        }

        // Retina対応: ピクセルサイズ→ポイントサイズに変換
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        nsImage.size = NSSize(
            width: nsImage.size.width / scale,
            height: nsImage.size.height / scale
        )

        let region = gifRecordingRegion
        gifRecordingRegion = nil

        let screenshot = Screenshot(image: nsImage, mode: .gifRecording, region: region)
        screenshot.savedURL = url
        currentScreenshot = screenshot

        // クリップボードにコピー
        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            _ = clipboardService.copyToClipboard(nsImage)
        }

        // 履歴に追加
        let entry = ScreenshotHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            mode: "GIF録画",
            filePath: url.path,
            width: Int(nsImage.size.width),
            height: Int(nsImage.size.height),
            windowX: region.map { Double($0.origin.x) },
            windowY: region.map { Double($0.origin.y) },
            windowW: region.map { Double($0.width) },
            windowH: region.map { Double($0.height) }
        )
        historyService.addEntry(entry)
        historyEntries = historyService.load()

        showEditorWindow(for: screenshot, at: region)
    }

    func openImageFromCLI(image: NSImage, filePath: String) {
        let screenshot = Screenshot(image: image, mode: .fullScreen)
        screenshot.savedURL = URL(fileURLWithPath: filePath)
        currentScreenshot = screenshot
        showEditorWindow(for: screenshot)
    }

    func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = .floating

        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url) else { return }

        let screenshot = Screenshot(image: nsImage, mode: .fullScreen)
        screenshot.savedURL = url
        currentScreenshot = screenshot
        showEditorWindow(for: screenshot)
    }

    private func showEditorWindow(for screenshot: Screenshot, at region: CGRect? = nil, showImageInitially: Bool = true, initialAnnotations: [any Annotation]? = nil) {
        // ResizableWindowを先に作成（独自のresizeStateを持つ）
        let window = ResizableWindow(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        // 各ウィンドウ独自のToolboxStateを作成
        let toolboxState = ToolboxState()

        // 復元するアノテーションがあればセット
        if let annotations = initialAnnotations {
            toolboxState.annotations = annotations
        }

        // PassThroughContainerViewを先に作成
        let containerView = PassThroughContainerView()

        let editorView = EditorWindow(screenshot: screenshot, resizeState: window.resizeState, toolboxState: toolboxState, parentWindow: window, onRecapture: { [weak self] rect, sourceWindow in
            guard let self = self else { return }
            Task {
                await self.recaptureRegion(for: screenshot, at: rect, window: sourceWindow)
            }
        }, onPassThroughChanged: { [weak window, weak containerView] enabled in
            containerView?.passThroughEnabled = enabled
            if let resizableWindow = window as? ResizableWindow {
                resizableWindow.passThroughEnabled = enabled
                resizableWindow.isMovableByWindowBackground = !enabled
            }
        }, onAnnotationsSaved: { [weak self] annotations in
            self?.saveAnnotationsToHistory(for: screenshot, annotations: annotations)
        }, showImageInitially: showImageInitially)
        let hostingController = NSHostingController(rootView: editorView)

        // PassThroughContainerViewでラップ
        containerView.autoresizingMask = [.width, .height]
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)
        window.contentView = containerView
        window.styleMask = [.borderless, .resizable]
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        window.isOpaque = false
        window.hasShadow = true
        // ピン設定に応じてウィンドウレベルを設定
        let pinBehavior = UserDefaults.standard.string(forKey: "pinBehavior") ?? "alwaysOn"
        switch pinBehavior {
        case "alwaysOn":
            window.level = .floating
        case "latestOnly":
            // 既存ウィンドウのピンを外す
            for info in editorWindows {
                if info.windowController.window?.level == .floating {
                    info.windowController.window?.level = .normal
                    NotificationCenter.default.post(name: .windowPinChanged, object: info.windowController.window)
                }
            }
            window.level = .floating
        case "off":
            window.level = .normal
        default:
            window.level = .floating
        }
        window.ignoresMouseEvents = false

        // regionが属するスクリーンの可視領域を使用
        let targetScreen = region.flatMap { NSScreen.screenContaining(cgRect: $0) } ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        // 範囲選択時は選択範囲と同じサイズ・位置
        if let region = region {
            let windowWidth = region.width
            let windowHeight = region.height

            window.setContentSize(NSSize(width: windowWidth, height: windowHeight))

            // CG座標（左上原点）からNS座標（左下原点）に変換
            let nsRect = NSScreen.cgToNS(region)
            let windowX = nsRect.origin.x
            let windowY = nsRect.origin.y

            // 画面内に収まるように調整
            let adjustedX = max(screenFrame.minX, min(windowX, screenFrame.maxX - windowWidth))
            let adjustedY = max(screenFrame.minY, min(windowY, screenFrame.maxY - windowHeight))

            window.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
        } else {
            let imageSize = screenshot.originalImage.size
            window.setContentSize(NSSize(width: imageSize.width, height: imageSize.height))
            window.center()
        }

        let windowController = NSWindowController(window: window)
        let windowInfo = EditorWindowInfo(
            id: UUID(),
            windowController: windowController,
            screenshot: screenshot,
            toolboxState: toolboxState,
            createdAt: Date()
        )
        editorWindows.append(windowInfo)
        windowController.showWindow(nil)

        // 閉じられたウィンドウをクリーンアップ
        cleanupClosedWindows()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func copyToClipboard() {
        guard let screenshot = currentScreenshot else { return }
        let finalImage = screenshot.renderFinalImage()
        _ = clipboardService.copyToClipboard(finalImage)
    }

    private func processScreenshot(_ screenshot: Screenshot) {
        // クリップボードにコピー（デフォルトはON）
        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            _ = clipboardService.copyToClipboard(screenshot.originalImage)
            print("Screenshot copied to clipboard")
        }

        // 自動保存（デフォルトはON）
        let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
        if autoSaveEnabled {
            let formatString = UserDefaults.standard.string(forKey: "defaultFormat") ?? "PNG"
            let format: FileStorageService.ImageFormat = formatString == "JPEG" ? .jpeg : .png
            let quality = UserDefaults.standard.double(forKey: "jpegQuality")

            do {
                let url = try fileStorageService.autoSaveImage(
                    screenshot.originalImage,
                    format: format,
                    quality: quality > 0 ? quality : 0.9
                )
                screenshot.savedURL = url
                print("Screenshot saved to: \(url.path)")

                // 履歴に追加
                let region = screenshot.captureRegion
                let entry = ScreenshotHistoryEntry(
                    id: UUID(),
                    timestamp: Date(),
                    mode: screenshot.mode.rawValue,
                    filePath: url.path,
                    width: Int(screenshot.originalImage.size.width),
                    height: Int(screenshot.originalImage.size.height),
                    windowX: region.map { Double($0.origin.x) },
                    windowY: region.map { Double($0.origin.y) },
                    windowW: region.map { Double($0.width) },
                    windowH: region.map { Double($0.height) }
                )
                historyService.addEntry(entry)
                historyEntries = historyService.load()
            } catch {
                print("Failed to auto-save screenshot: \(error)")
            }
        }
    }

    // MARK: - エディターウィンドウ管理

    /// 閉じられたウィンドウをクリーンアップ
    func cleanupClosedWindows() {
        editorWindows.removeAll { info in
            info.windowController.window == nil || !info.windowController.window!.isVisible
        }
    }

    /// 特定のエディターウィンドウを閉じる
    func closeEditorWindow(_ windowInfo: EditorWindowInfo) {
        windowInfo.windowController.window?.close()
        editorWindows.removeAll { $0.id == windowInfo.id }
    }

    /// すべてのエディターウィンドウを閉じる
    func closeAllEditorWindows() {
        for windowInfo in editorWindows {
            windowInfo.windowController.window?.close()
        }
        editorWindows.removeAll()
    }

    /// 開いているエディターウィンドウの数
    var openEditorWindowCount: Int {
        return editorWindows.filter { info in
            info.windowController.window != nil && info.windowController.window!.isVisible
        }.count
    }

    // MARK: - 履歴管理

    func openFromHistory(_ entry: ScreenshotHistoryEntry) {
        // アノテーションがある場合はベース画像（元画像）を使用
        let imageURL: URL
        if let basePath = entry.baseFilePath, entry.hasAnnotations == true,
           FileManager.default.fileExists(atPath: basePath) {
            imageURL = URL(fileURLWithPath: basePath)
        } else {
            imageURL = URL(fileURLWithPath: entry.filePath)
        }

        let isGifEntry = entry.mode == "GIF録画"

        guard let nsImage = NSImage(contentsOf: imageURL) else {
            // ファイルが存在しない場合は履歴から削除
            removeHistoryEntry(id: entry.id)
            return
        }

        // Retina対応: NSImageのサイズをポイント単位に修正（GIFはGifPlayerStateで処理するのでここでは補正）
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let pointWidth = nsImage.size.width / scale
        let pointHeight = nsImage.size.height / scale
        nsImage.size = NSSize(width: pointWidth, height: pointHeight)

        // 保存されたウィンドウ位置を復元、なければ画面中央
        let region: CGRect
        if let wx = entry.windowX, let wy = entry.windowY, let ww = entry.windowW, let wh = entry.windowH {
            region = CGRect(x: wx, y: wy, width: ww, height: wh)
        } else {
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let x = (screenFrame.width - pointWidth) / 2
            let y = (screenFrame.height - pointHeight) / 2
            region = CGRect(x: x, y: y, width: pointWidth, height: pointHeight)
        }

        let captureMode: CaptureMode = isGifEntry ? .gifRecording : (entry.mode == "全画面" ? .fullScreen : .region)
        let screenshot = Screenshot(image: nsImage, mode: captureMode, region: region)
        screenshot.savedURL = URL(fileURLWithPath: entry.filePath)
        currentScreenshot = screenshot

        // アノテーションを復元（個別ファイルから読み込み）
        var restoredAnnotations: [any Annotation]? = nil
        if entry.hasAnnotations == true,
           let codableAnnotations = historyService.loadAnnotations(id: entry.id), !codableAnnotations.isEmpty {
            restoredAnnotations = codableAnnotations.compactMap { $0.toAnnotation(sourceImage: nsImage) }
        }

        showEditorWindow(for: screenshot, at: region, initialAnnotations: restoredAnnotations)
    }

    func removeHistoryEntry(id: UUID) {
        // 表示中のエディタウィンドウがあれば閉じる
        if let entry = historyEntries.first(where: { $0.id == id }),
           let windowInfo = editorWindows.first(where: { $0.screenshot.savedURL?.path == entry.filePath }) {
            closeEditorWindow(windowInfo)
        }
        historyService.removeEntry(id: id)
        historyEntries = historyService.load()
    }

    func toggleFavorite(id: UUID) {
        historyService.toggleFavorite(id: id)
        historyEntries = historyService.load()
    }

    private func saveAnnotationsToHistory(for screenshot: Screenshot, annotations: [any Annotation]) {
        guard let filePath = screenshot.savedURL?.path else { return }

        let codable = annotations.compactMap { CodableAnnotation.from($0) }

        // ベース画像（アノテーション適用前の元画像）を保存
        var baseFilePath: String? = nil
        if !codable.isEmpty {
            let fileURL = URL(fileURLWithPath: filePath)
            let baseName = fileURL.deletingPathExtension().lastPathComponent + "_base"
            let ext = fileURL.pathExtension
            let baseURL = fileURL.deletingLastPathComponent().appendingPathComponent(baseName).appendingPathExtension(ext)

            // まだベース画像がなければ保存
            if !FileManager.default.fileExists(atPath: baseURL.path) {
                if let tiffData = screenshot.originalImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    let pngData: Data?
                    if ext.lowercased() == "jpg" || ext.lowercased() == "jpeg" {
                        pngData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    } else {
                        pngData = bitmap.representation(using: .png, properties: [:])
                    }
                    if let data = pngData {
                        try? data.write(to: baseURL)
                    }
                }
            }
            baseFilePath = baseURL.path
        }

        historyService.updateAnnotations(forFilePath: filePath, annotations: codable.isEmpty ? nil : codable, baseFilePath: baseFilePath)
        historyEntries = historyService.load()
    }

    func flashEditorWindow(for entry: ScreenshotHistoryEntry) {
        cleanupClosedWindows()
        guard let existing = editorWindows.first(where: { $0.screenshot.savedURL?.path == entry.filePath }),
              let window = existing.windowController.window else { return }

        // latestOnlyの場合、ピンをこのウィンドウに切り替え
        let pinBehavior = UserDefaults.standard.string(forKey: "pinBehavior") ?? "alwaysOn"
        if pinBehavior == "latestOnly" {
            for info in editorWindows {
                if info.windowController.window?.level == .floating && info.id != existing.id {
                    info.windowController.window?.level = .normal
                    NotificationCenter.default.post(name: .windowPinChanged, object: info.windowController.window)
                }
            }
            window.level = .floating
            NotificationCenter.default.post(name: .windowPinChanged, object: window)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let frame = window.frame
        // NS座標（左下原点）→CG座標（左上原点）に変換
        let primaryHeight = NSScreen.primaryScreenHeight
        let topLeftRect = CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        captureFlash.showFlash(in: topLeftRect)
    }

    func cleanupInvalidHistoryEntries() {
        historyEntries = historyService.removeInvalidEntries()
    }

    // MARK: - 履歴ウィンドウ管理

    func showHistoryWindow() {
        // 既に表示中なら前面に出す
        if let window = historyWindowController?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 無効なエントリをクリーンアップ
        cleanupInvalidHistoryEntries()

        // Dockアイコンを表示
        NSApp.setActivationPolicy(.regular)

        let historyView = HistoryWindow(viewModel: self)
        let hostingController = NSHostingController(rootView: historyView)

        let window = ClickThroughWindow(contentViewController: hostingController)
        window.title = "ライブラリ"
        window.setContentSize(NSSize(width: 400, height: 480))
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.minSize = NSSize(width: 400, height: 300)

        // 保存された位置を復元、なければ右上に配置
        if let frameStr = UserDefaults.standard.string(forKey: "libraryWindowFrame") {
            window.setFrame(NSRectFromString(frameStr), display: true)
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let x = screenFrame.maxX - 400 - 20
            let y = screenFrame.maxY - 480 - 20
            window.setFrame(NSRect(x: x, y: y, width: 400, height: 480), display: true)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.45, green: 0.32, blue: 0.18, alpha: 1.0)

        // カスタムタイトル（アイコン＋白文字）
        let titleBar = window.standardWindowButton(.closeButton)?.superview
        let titleBarHeight = titleBar?.frame.height ?? 28
        let titleContainer = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: titleBarHeight))
        let titleLabel = NSTextField(labelWithString: "")
        let titleAttachment = NSTextAttachment()
        titleAttachment.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        let attrStr = NSMutableAttributedString(attachment: titleAttachment)
        attrStr.append(NSAttributedString(string: " ライブラリ"))
        attrStr.addAttributes([
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ], range: NSRange(location: 0, length: attrStr.length))
        titleLabel.attributedStringValue = attrStr
        titleLabel.alignment = .center
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(
            x: 0,
            y: (titleBarHeight - titleLabel.frame.height) / 2
        )
        titleContainer.addSubview(titleLabel)
        titleContainer.frame.size.width = titleLabel.frame.width
        let titleAccessory = NSTitlebarAccessoryViewController()
        titleAccessory.view = titleContainer
        titleAccessory.layoutAttribute = .leading
        window.addTitlebarAccessoryViewController(titleAccessory)

        // タイトルバーにピンボタンを追加
        let pinButton = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "ピン")
        pinButton.contentTintColor = .white
        pinButton.target = self
        pinButton.action = #selector(toggleHistoryWindowPin(_:))
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = pinButton
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        let delegate = HistoryWindowDelegateHandler { [weak self] in
            self?.onHistoryWindowClosed()
        }
        self.historyWindowDelegate = delegate
        window.delegate = delegate

        let controller = NSWindowController(window: window)
        historyWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func toggleHistoryWindowPin(_ sender: NSButton) {
        guard let window = historyWindowController?.window else { return }
        if window.level == .floating {
            window.level = .normal
            sender.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "ピン")
        } else {
            window.level = .floating
            sender.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "ピン解除")
        }
    }

    func closeHistoryWindow() {
        historyWindowController?.window?.close()
        historyWindowController = nil
        onHistoryWindowClosed()
    }

    private func onHistoryWindowClosed() {
        historyWindowController = nil
        historyWindowDelegate = nil
        // Dockアイコンを非表示に戻す
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - 非アクティブでもクリック可能なウィンドウ

class ClickThroughWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // 非アクティブ時のマウスクリックもそのまま処理する
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

// MARK: - 履歴ウィンドウのデリゲート

class HistoryWindowDelegateHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "libraryWindowFrame")
        }
        DispatchQueue.main.async { [weak self] in
            self?.onClose()
        }
    }
}
