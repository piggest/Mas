import SwiftUI
import UniformTypeIdentifiers

@MainActor
class CaptureViewModel: ObservableObject {
    @Published var isCapturing = false
    @Published var currentScreenshot: Screenshot?
    @Published var errorMessage: String?
    @Published var availableWindows: [ScreenCaptureService.WindowInfo] = []

    private let captureService = ScreenCaptureService()
    private let clipboardService = ClipboardService()
    private let fileStorageService = FileStorageService()
    private let permissionService = PermissionService()
    private let captureFlash = CaptureFlashView()

    // エディターウィンドウ情報（メニュー表示用）
    struct EditorWindowInfo: Identifiable {
        let id: UUID
        let windowController: NSWindowController
        let screenshot: Screenshot
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

    init() {
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
            selector: #selector(handleCaptureWindow),
            name: .captureWindow,
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

    @objc private func handleCaptureWindow() {
        Task { await loadAvailableWindows() }
    }

    @objc private func handleShowCaptureFrame() {
        Task { await showCaptureFrame() }
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

    // デフォルトのキャプチャ範囲（画面中央、幅1/3）
    private func defaultCaptureRect() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 100, y: 100, width: 400, height: 300)
        }
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height
        let frameWidth = screenWidth / 3
        let frameHeight = frameWidth * 0.75 // 4:3のアスペクト比
        let x = (screenWidth - frameWidth) / 2
        let y = (screenHeight - frameHeight) / 2
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

        do {
            try await Task.sleep(nanoseconds: 200_000_000)

            let cgImage = try await captureService.captureFullScreen()

            // 画面全体をregionとして設定
            guard let screen = NSScreen.main else {
                errorMessage = "ディスプレイが見つかりません"
                isCapturing = false
                return
            }
            let fullScreenRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)

            let screenshot = Screenshot(cgImage: cgImage, mode: .fullScreen, region: fullScreenRect)
            currentScreenshot = screenshot
            captureFlash.showFlash(in: fullScreenRect)
            processScreenshot(screenshot)
            showEditorWindow(for: screenshot, at: fullScreenRect)
        } catch {
            errorMessage = error.localizedDescription
            print("Capture error: \(error)")
        }

        isCapturing = false
    }

    func startRegionSelection() async {
        guard !isCapturing else { return }
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        do {
            // 先に画面全体をキャプチャしておく
            let fullScreenImage = try await captureService.captureFullScreen()

            let overlay = RegionSelectionOverlay(onComplete: { [weak self] rect in
                guard let self = self else { return }
                Task {
                    await self.cropRegion(rect, from: fullScreenImage)
                }
            }, onCancel: { [weak self] in
                self?.isCapturing = false
            })
            overlay.show()
        } catch {
            errorMessage = error.localizedDescription
            print("Capture error: \(error)")
            isCapturing = false
        }
    }

    private func cropRegion(_ rect: CGRect, from fullImage: CGImage) async {
        guard let screen = NSScreen.main else {
            errorMessage = "ディスプレイが見つかりません"
            isCapturing = false
            return
        }

        let imageWidth = CGFloat(fullImage.width)
        let imageHeight = CGFloat(fullImage.height)

        // スケール計算（Retina対応）
        let scale = imageWidth / screen.frame.width

        // rectは既に左上原点座標なので、スケールのみ適用
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
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
        print("=== Recapture started ===")
        print("Region: \(region)")

        // ウィンドウを一時的に隠す
        print("Window: \(String(describing: window))")
        window?.orderOut(nil)

        // 少し待つ
        try? await Task.sleep(nanoseconds: 200_000_000)

        do {
            let fullScreenImage = try await captureService.captureFullScreen()
            print("Full screen image size: \(fullScreenImage.width) x \(fullScreenImage.height)")

            guard let screen = NSScreen.main else {
                print("No screen found")
                window?.makeKeyAndOrderFront(nil)
                return
            }

            let imageWidth = CGFloat(fullScreenImage.width)
            let imageHeight = CGFloat(fullScreenImage.height)
            let scale = imageWidth / screen.frame.width
            print("Scale: \(scale), Screen width: \(screen.frame.width)")

            let scaledRect = CGRect(
                x: region.origin.x * scale,
                y: region.origin.y * scale,
                width: region.width * scale,
                height: region.height * scale
            )
            print("Scaled rect: \(scaledRect)")

            let clampedRect = scaledRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            print("Clamped rect: \(clampedRect)")

            guard !clampedRect.isEmpty, let croppedImage = fullScreenImage.cropping(to: clampedRect) else {
                print("Cropping failed")
                window?.makeKeyAndOrderFront(nil)
                return
            }

            print("Cropped image size: \(croppedImage.width) x \(croppedImage.height)")

            // フラッシュアニメーション
            captureFlash.showFlash(in: region)

            // 画像と範囲を更新
            screenshot.updateImage(croppedImage)
            screenshot.captureRegion = region
            print("Image updated")

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
            print("=== Recapture completed ===")
        } catch {
            print("Recapture error: \(error)")
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func loadAvailableWindows() async {
        availableWindows = captureService.getAvailableWindows()
    }

    func captureWindow(_ window: ScreenCaptureService.WindowInfo) async {
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        do {
            let cgImage = try await captureService.captureWindow(windowID: window.id)
            // ウィンドウのboundsをregionとして使用
            let screenshot = Screenshot(cgImage: cgImage, mode: .window, region: window.bounds)
            currentScreenshot = screenshot
            captureFlash.showFlash(in: window.bounds)
            processScreenshot(screenshot)
            showEditorWindow(for: screenshot, at: window.bounds)
        } catch {
            errorMessage = error.localizedDescription
            print("Window capture error: \(error)")
        }

        isCapturing = false
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

    private func showEditorWindow(for screenshot: Screenshot, at region: CGRect? = nil, showImageInitially: Bool = true) {
        // ResizableWindowを先に作成（独自のresizeStateを持つ）
        let window = ResizableWindow(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        // 各ウィンドウ独自のToolboxStateを作成
        let toolboxState = ToolboxState()

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

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        // 範囲選択時は選択範囲と同じサイズ・位置
        if let region = region {
            let windowWidth = region.width
            let windowHeight = region.height

            window.setContentSize(NSSize(width: windowWidth, height: windowHeight))

            // 左上原点から左下原点に変換
            let screenHeight = NSScreen.main?.frame.height ?? 0
            let windowX = region.origin.x
            let windowY = screenHeight - region.origin.y - windowHeight

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
}
