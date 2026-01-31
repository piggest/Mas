import SwiftUI

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
    private var editorWindowController: NSWindowController?

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
        guard await checkPermission() else { return }

        isCapturing = true
        errorMessage = nil

        do {
            // 先に画面全体をキャプチャしておく
            let fullScreenImage = try await captureService.captureFullScreen()

            // 少し待ってからオーバーレイを表示
            try await Task.sleep(nanoseconds: 100_000_000)

            let overlay = RegionSelectionOverlay { [weak self] rect in
                guard let self = self else { return }
                Task {
                    await self.cropRegion(rect, from: fullScreenImage)
                }
            }
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
        isCapturing = false
    }

    // 再キャプチャ機能（現在のウィンドウ位置で）
    func recaptureRegion(for screenshot: Screenshot, at region: CGRect) async {
        print("=== Recapture started ===")
        print("Region: \(region)")

        // ウィンドウを一時的に隠す
        let window = editorWindowController?.window
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
            WindowResizeState.shared.reset()

            // 新しい画像を保存
            processScreenshot(screenshot)

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

    private var passThroughContainerView: PassThroughContainerView?

    private func showEditorWindow(for screenshot: Screenshot, at region: CGRect? = nil) {
        let editorView = EditorWindow(screenshot: screenshot, onRecapture: { [weak self] rect in
            guard let self = self else { return }
            Task {
                await self.recaptureRegion(for: screenshot, at: rect)
            }
        }, onPassThroughChanged: { [weak self] enabled in
            self?.passThroughContainerView?.passThroughEnabled = enabled
            if let window = self?.editorWindowController?.window as? ResizableWindow {
                window.passThroughEnabled = enabled
                window.isMovableByWindowBackground = !enabled
            }
        })
        let hostingController = NSHostingController(rootView: editorView)

        // PassThroughContainerViewでラップ
        let containerView = PassThroughContainerView()
        containerView.autoresizingMask = [.width, .height]
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)
        passThroughContainerView = containerView

        // リサイズ状態をリセット
        WindowResizeState.shared.reset()

        let window = ResizableWindow(contentRect: .zero, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.contentView = containerView
        window.styleMask = [.borderless, .resizable]
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
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

        editorWindowController = NSWindowController(window: window)
        editorWindowController?.showWindow(nil)

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
}
