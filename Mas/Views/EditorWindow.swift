import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// VideoLayerView / VideoPlayerView / GifFrameView は Mas/Views/Editor/EditorVideoView.swift に移動済み
// NoHighlightButtonStyle / EditTool / FlatTextChar / CaptureActionMode は Mas/Views/Editor/EditorTypes.swift に移動済み
// DraggableImageView / DragSourceView は Mas/Views/Editor/EditorDragSource.swift に移動済み

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @ObservedObject var toolboxState: ToolboxState
    @ObservedObject var resizeState: WindowResizeState
    @State var copiedToClipboard = false
    @State private var showImage: Bool
    @State var contentYOffset: CGFloat = 0
    @State private var passThroughEnabled = false
    @State private var editMode = false
    @State private var captureActionMode: CaptureActionMode = .recapture
    @State private var currentAnnotation: (any Annotation)?
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero
    @FocusState private var isTextFieldFocused: Bool
    @State var toolbarController: FloatingToolbarWindowController?
    @State private var isLoadingAnnotationAttributes = false
    @State var imageForDrag: NSImage?  // アノテーション付きドラッグ用画像
    @State private var editingTextIndex: Int?  // 編集中のテキストアノテーションのインデックス
    @State private var arrowTextStartPoint: CGPoint?  // 矢印文字ツール：矢印の始点
    @State private var arrowTextEndPoint: CGPoint?    // 矢印文字ツール：矢印の終点
    @State private var alwaysOnTop: Bool = true
    @State private var contentScale: CGFloat = 1.0
    @State private var contentPanOffset: CGSize = .zero
    @State private var panStartOffset: CGSize = .zero
    @State private var isPanning: Bool = false
    // テキスト選択モード（文字単位選択）
    @State var recognizedTexts: [RecognizedTextBlock] = []
    @State var isRecognizingText = false
    @State var flatChars: [FlatTextChar] = []
    @State var charSelStart: Int?
    @State var charSelEnd: Int?
    let textRecognitionService = TextRecognitionService()
    @State private var keyMonitor: Any?
    @State private var middleMouseMonitor: Any?

    // GIF再生
    @State var gifPlayerState: GifPlayerState?
    @State private var gifToolbarController: GifPlayerToolbarController?

    // 動画再生
    @State var videoPlayerState: VideoPlayerState?
    @State var videoToolbarController: VideoPlayerToolbarController?

    // シャッターオプション
    @State private var shutterPanelController: ShutterOptionsPanelController?

    // ファイルドロップ受け入れ状態（外部画像ファイルをドラッグ中のハイライト用）
    @State private var isDropTargeted: Bool = false

    let onRecapture: ((CGRect, NSWindow?, Bool) -> Void)?
    let onPassThroughChanged: ((Bool) -> Void)?
    let onAnnotationsSaved: (([any Annotation]) -> Void)?
    weak var parentWindow: NSWindow?

    init(screenshot: Screenshot, resizeState: WindowResizeState, toolboxState: ToolboxState, parentWindow: NSWindow? = nil, onRecapture: ((CGRect, NSWindow?, Bool) -> Void)? = nil, onPassThroughChanged: ((Bool) -> Void)? = nil, onAnnotationsSaved: (([any Annotation]) -> Void)? = nil, showImageInitially: Bool = true, initialContentScale: CGFloat = 1.0) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.resizeState = resizeState
        self.toolboxState = toolboxState
        self.parentWindow = parentWindow
        self.onRecapture = onRecapture
        self.onPassThroughChanged = onPassThroughChanged
        self.onAnnotationsSaved = onAnnotationsSaved
        _showImage = State(initialValue: showImageInitially)
        _contentScale = State(initialValue: initialContentScale)
        // 撮影モードに応じてキャプチャアクションの初期値を設定
        switch screenshot.mode {
        case .gifRecording:
            _captureActionMode = State(initialValue: .gif)
        case .videoRecording:
            _captureActionMode = State(initialValue: .video)
        default:
            _captureActionMode = State(initialValue: .recapture)
        }
    }

    private func getCurrentWindowRect() -> CGRect {
        guard let window = parentWindow else {
            return screenshot.captureRegion ?? .zero
        }
        return CaptureRegionMath.windowFrameToCaptureRegion(
            nsFrame: window.frame,
            primaryHeight: NSScreen.primaryScreenHeight
        )
    }

    // 外部からドロップされた画像ファイルを枠に取り込む
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // 動画/GIFモードでは差し替えを行わない（既存プレイヤーとの整合性のため）
        if screenshot.isVideo || screenshot.isGif {
            return false
        }

        // ファイルURL経由（Finder からのドラッグ等）
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let fileURL = url, let image = NSImage(contentsOf: fileURL) else { return }
                DispatchQueue.main.async {
                    applyDroppedImage(image)
                }
            }
            return true
        }

        // 画像データ経由（ブラウザ等からのドラッグ）
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage else { return }
                DispatchQueue.main.async {
                    applyDroppedImage(image)
                }
            }
            return true
        }

        return false
    }

    // ドロップされた画像でスクリーンショットを差し替え、枠サイズも合わせる
    private func applyDroppedImage(_ image: NSImage) {
        // 編集モード解除
        if editMode {
            editMode = false
        }

        // アノテーションをリセット（旧画像用のものを残さない）
        toolboxState.annotations.removeAll()
        toolboxState.selectedAnnotationIndex = nil

        // 画像を差し替え
        screenshot.originalImage = image

        // captureRegion のサイズを画像に合わせて更新（位置は保持）
        let newSize = image.size
        if let oldRegion = screenshot.captureRegion {
            screenshot.captureRegion = CGRect(
                x: oldRegion.origin.x,
                y: oldRegion.origin.y,
                width: newSize.width,
                height: newSize.height
            )
        } else {
            screenshot.captureRegion = CGRect(origin: .zero, size: newSize)
        }

        // リサイズ用オフセット状態をリセット
        resizeState.reset()

        // ドラッグ用キャッシュをクリア
        imageForDrag = nil

        // 画像を表示状態に
        showImage = true

        // 画面に収まるようスケールを計算し setContentScale 経由でウィンドウサイズと contentScale を同期
        // （これにより以後のコンテンツサイズ縮小メニューも正しく機能する）
        if let window = parentWindow, newSize.width > 0, newSize.height > 0 {
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let fitScale = CaptureRegionMath.initialContentScale(
                contentSize: newSize,
                screenVisibleSize: screenFrame.size
            )
            setContentScale(fitScale)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                imageContent
                    .offset(contentPanOffset)
                    .scaleEffect(contentScale, anchor: .topLeading)
                closeButton
                pinButton
                editModeToggle(geometry: geometry)
                topRightButtons(geometry: geometry)
                dragArea(geometry: geometry)

                // インラインテキスト入力（有効化）
                if showTextInput {
                    inlineTextInput
                }

                // 編集モード以外でドラッグ中のオーバーレイ
                if !editMode && resizeState.isDragging {
                    Color.black.opacity(0.3)
                        .allowsHitTesting(false)
                }

                // 外部ファイルドロップ中のハイライト
                if isDropTargeted {
                    Color.accentColor.opacity(0.18)
                        .allowsHitTesting(false)
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 50, minHeight: 50)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !editMode {
                showImage = false
            }
        }
        .border(Color.gray.opacity(0.5), width: 1)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers: providers)
        }
        .contextMenu {
            Button("閉じる") { closeWindow() }
            Divider()
            Button("クリップボードにコピー") { copyToClipboard() }
            Divider()
            if !screenshot.isVideo {
                Button(editMode ? "編集を終了" : "編集") {
                    if !editMode {
                        editMode = true
                    } else {
                        // editModeToggleと同じ終了処理をトリガー
                        editMode = false
                    }
                }
                Divider()
            }
            Menu("コンテンツサイズ") {
                Button("50%") { setContentScale(0.5) }
                Button("75%") { setContentScale(0.75) }
                Button("100%") { setContentScale(1.0) }
                Button("150%") { setContentScale(1.5) }
                Button("200%") { setContentScale(2.0) }
            }
            if screenshot.captureRegion != nil {
                Divider()
                Menu("シャッター") {
                    ForEach(ShutterTab.allCases, id: \.self) { mode in
                        Button {
                            openShutterMode(mode)
                        } label: {
                            Label(mode.rawValue, systemImage: mode.icon)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowPinChanged)) { notification in
            if let window = notification.object as? NSWindow, window === parentWindow {
                alwaysOnTop = window.level == .floating
            }
        }
        .onAppear {
            toolbarController = FloatingToolbarWindowController()
            alwaysOnTop = parentWindow?.level == .floating

            // 中ボタンドラッグでコンテンツパン
            middleMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [self] event in
                guard event.buttonNumber == 2,
                      event.window === parentWindow else { return event }
                switch event.type {
                case .otherMouseDown:
                    isPanning = true
                    panStartOffset = contentPanOffset
                case .otherMouseDragged:
                    if isPanning {
                        contentPanOffset = CGSize(
                            width: panStartOffset.width + event.deltaX,
                            height: panStartOffset.height + event.deltaY
                        )
                        // deltaは累積ではなく差分なので毎回更新
                        panStartOffset = contentPanOffset
                    }
                case .otherMouseUp:
                    isPanning = false
                default:
                    break
                }
                return nil // イベント消費
            }

            // GIFモード: プレイヤー初期化 + ツールバー表示 + 自動再生
            if screenshot.isGif, let url = screenshot.savedURL {
                if let player = GifPlayerState(url: url) {
                    gifPlayerState = player
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let parent = self.parentWindow {
                            let controller = GifPlayerToolbarController()
                            controller.show(attachedTo: parent, playerState: player)
                            self.gifToolbarController = controller
                        }
                        player.play()
                    }
                }
            }

            // 動画モード: プレイヤー初期化 + ツールバー表示 + 自動再生
            if screenshot.isVideo, let url = screenshot.savedURL {
                if let player = VideoPlayerState(url: url) {
                    videoPlayerState = player
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let parent = self.parentWindow {
                            let controller = VideoPlayerToolbarController()
                            controller.show(attachedTo: parent, playerState: player, onTrimComplete: { [self] trimmedURL in
                                // トリムしたファイルで現在のウィンドウを置き換え
                                self.replaceWithTrimmedVideo(url: trimmedURL)
                            }, onGifExportComplete: { [self] gifURL in
                                self.handleGifExportComplete(url: gifURL)
                            })
                            self.videoToolbarController = controller
                        }
                        player.play()
                    }
                }
            }
        }
        .onDisappear {
            toolbarController?.close()
            gifPlayerState?.pause()
            gifToolbarController?.close()
            videoPlayerState?.pause()
            videoToolbarController?.close()
            shutterPanelController?.close()
            shutterPanelController = nil
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = middleMouseMonitor {
                NSEvent.removeMonitor(monitor)
                middleMouseMonitor = nil
            }
        }
        .onChange(of: editMode) { newValue in
            // 編集モード中はウィンドウのドラッグ移動を無効化
            if let resizableWindow = parentWindow as? ResizableWindow {
                resizableWindow.isMovableByWindowBackground = !newValue && !passThroughEnabled
            }
            if newValue {
                // テキスト選択モードのままだとアノテーション操作不能になるのでリセット
                if toolboxState.selectedTool == .textSelection {
                    toolboxState.selectedTool = .arrow
                }
                // GIF: 編集開始時に再生停止 + プレーヤーツールバーを閉じる
                if screenshot.isGif {
                    gifPlayerState?.pause()
                    gifToolbarController?.close()
                }
                showToolbar()
            } else {
                // テキスト入力をキャンセル
                if showTextInput {
                    showTextInput = false
                    textInput = ""
                    isTextFieldFocused = false
                }
                currentAnnotation = nil
                // ツールバーを閉じる（SwiftUI更新サイクル外で実行）
                let controller = toolbarController
                toolbarController = nil
                DispatchQueue.main.async {
                    controller?.close()
                }
                // GIF: 編集終了時にプレーヤーツールバーを再表示 + 再生再開
                if screenshot.isGif {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if let parent = self.parentWindow, let player = self.gifPlayerState {
                            let ctrl = GifPlayerToolbarController()
                            ctrl.show(attachedTo: parent, playerState: player)
                            self.gifToolbarController = ctrl
                            player.play()
                        }
                    }
                }
            }
        }
        .onChange(of: toolboxState.selectedColor) { newColor in
            updateSelectedAnnotationColor(newColor)
        }
        .onChange(of: toolboxState.lineWidth) { newWidth in
            updateSelectedAnnotationLineWidth(newWidth)
        }
        .onChange(of: toolboxState.strokeEnabled) { newEnabled in
            updateSelectedAnnotationStroke(newEnabled)
        }
        .onChange(of: toolboxState.selectedAnnotationIndex) { newIndex in
            loadSelectedAnnotationAttributes(at: newIndex)
        }
        .onChange(of: toolboxState.selectedTool) { newTool in
            // テキスト入力中に別のツールに切り替えたら入力をキャンセル
            if showTextInput && newTool != .text && newTool != .arrowText {
                cancelTextInput()
            }
            // テキスト選択モードの切替
            if newTool == .textSelection {
                startTextRecognition()
                // Cmd+Cでコピーできるようにキーイベントモニターを設定
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                        copySelectedText()
                        return nil
                    }
                    return event
                }
            } else {
                recognizedTexts = []
                flatChars = []
                charSelStart = nil
                charSelEnd = nil
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
            }
        }
    }

    private func updateSelectedAnnotationColor(_ color: Color) {
        guard !isLoadingAnnotationAttributes,
              toolboxState.selectedTool == .move,
              let index = toolboxState.selectedAnnotationIndex,
              index < toolboxState.annotations.count else { return }
        // SwiftUI Colorから独立したNSColorを作成（クラッシュ防止）
        toolboxState.annotations[index].annotationColor = Self.createIndependentNSColor(from: color)
        // 配列の変更を通知して再描画をトリガー
        toolboxState.objectWillChange.send()
    }

    private func updateSelectedAnnotationLineWidth(_ width: CGFloat) {
        guard !isLoadingAnnotationAttributes,
              toolboxState.selectedTool == .move,
              let index = toolboxState.selectedAnnotationIndex,
              index < toolboxState.annotations.count else { return }
        toolboxState.annotations[index].annotationLineWidth = width
        // 配列の変更を通知して再描画をトリガー
        toolboxState.objectWillChange.send()
    }

    private func updateSelectedAnnotationStroke(_ enabled: Bool) {
        guard !isLoadingAnnotationAttributes,
              toolboxState.selectedTool == .move,
              let index = toolboxState.selectedAnnotationIndex,
              index < toolboxState.annotations.count else { return }
        toolboxState.annotations[index].annotationStrokeEnabled = enabled
        // 配列の変更を通知して再描画をトリガー
        toolboxState.objectWillChange.send()
    }

    private func loadSelectedAnnotationAttributes(at index: Int?) {
        // 選択が発生した時点でmoveモードのはず（キャンバスがチェック済み）
        guard let index = index,
              index < toolboxState.annotations.count else {
            return
        }

        isLoadingAnnotationAttributes = true
        // 同期タイマーを一時停止（上書きを防ぐ）
        toolbarController?.pauseSync()

        let annotation = toolboxState.annotations[index]
        if let color = annotation.annotationColor {
            toolboxState.selectedColor = Color(color)
        }
        if let width = annotation.annotationLineWidth {
            toolboxState.lineWidth = width
        }
        if let stroke = annotation.annotationStrokeEnabled {
            toolboxState.strokeEnabled = stroke
        }

        // ツールバーに属性を反映して同期を再開
        toolbarController?.syncAttributesFromState()
        toolbarController?.resumeSync()
        isLoadingAnnotationAttributes = false
    }

    private func showToolbar() {
        // 親ウィンドウにツールバーを表示
        guard let window = parentWindow else { return }

        // toolbarControllerがnilの場合は新規作成
        if toolbarController == nil {
            toolbarController = FloatingToolbarWindowController()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.toolbarController?.show(
                attachedTo: window,
                state: self.toolboxState,
                onUndo: {
                    _ = self.toolboxState.annotations.popLast()
                },
                onDelete: {
                    self.deleteSelectedAnnotation()
                },
                onClose: {
                    self.editMode = false
                }
            )
        }
    }

    private func deleteSelectedAnnotation() {
        guard let index = toolboxState.selectedAnnotationIndex,
              index < toolboxState.annotations.count else { return }

        toolboxState.annotations.remove(at: index)

        // 削除後に次のアノテーションを自動選択
        if toolboxState.annotations.isEmpty {
            toolboxState.selectedAnnotationIndex = nil
        } else if index < toolboxState.annotations.count {
            // 同じ位置に次のアノテーションがあればそれを選択
            toolboxState.selectedAnnotationIndex = index
        } else {
            // 最後の要素だった場合は一つ前を選択
            toolboxState.selectedAnnotationIndex = toolboxState.annotations.count - 1
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        let offsetX = resizeState.originDelta.x
        let offsetY = resizeState.originDelta.y

        GeometryReader { geometry in
            let imageWidth = screenshot.captureRegion?.width ?? screenshot.originalImage.size.width
            let imageHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height

            ZStack(alignment: .topLeading) {
                if showImage {
                    screenshotImage
                        .offset(y: contentYOffset)
                } else {
                    Color.clear
                        .frame(width: imageWidth, height: imageHeight)
                        .offset(y: contentYOffset)
                }
                // 編集モード中、またはアノテーションがある場合にcanvasを表示
                // ウィンドウ全体に広げてアノテーションのはみ出しを表示可能に
                // 動画モードではアノテーション非対応
                if !screenshot.isVideo, editMode || !toolboxState.annotations.isEmpty {
                    let extraX = max(0, geometry.size.width - imageWidth)
                    let extraY = max(0, geometry.size.height - imageHeight)
                    annotationCanvas
                        .frame(
                            width: imageWidth + extraX * 2,
                            height: imageHeight + extraY * 2
                        )
                        .offset(x: -extraX, y: -extraY + contentYOffset)
                }
            }
            .offset(x: offsetX, y: offsetY)
        }
    }

    @ViewBuilder
    private var screenshotImage: some View {
        if screenshot.isVideo, let playerState = videoPlayerState {
            // 動画モード: AVPlayerLayerで再生
            VideoPlayerView(player: playerState.player)
                .frame(
                    width: screenshot.captureRegion?.width ?? screenshot.originalImage.size.width,
                    height: screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    playerState.togglePlayPause()
                }
        } else if let gifPlayer = gifPlayerState {
            // GIFモード: GifFrameView(@ObservedObject)でフレーム変更を監視
            GifFrameView(playerState: gifPlayer, region: screenshot.captureRegion)
        } else if let region = screenshot.captureRegion {
            Image(nsImage: screenshot.originalImage)
                .resizable()
                .frame(width: region.width, height: region.height)
        } else {
            Image(nsImage: screenshot.originalImage)
        }
    }

    private var annotationCanvas: some View {
        // SwiftUI Colorから独立したNSColorを作成（クラッシュ防止）
        let safeColor = Self.createIndependentNSColor(from: toolboxState.selectedColor)
        return AnnotationCanvasView(
            annotations: $toolboxState.annotations,
            currentAnnotation: $currentAnnotation,
            selectedTool: toolboxState.selectedTool,
            selectedColor: safeColor,
            lineWidth: toolboxState.lineWidth,
            strokeEnabled: toolboxState.strokeEnabled,
            sourceImage: gifPlayerState?.currentFrameImage ?? screenshot.originalImage,
            isEditing: editMode,
            showImage: showImage,
            toolboxState: toolboxState,
            onTextTap: { position in
                textPosition = position
                showTextInput = true
            },
            onArrowTextDragFinished: { [self] startPoint, endPoint in
                // 矢印アノテーションを直接追加（annotationAddedを経由するとmoveに切り替わるため）
                let safeColor = Self.createIndependentNSColor(from: toolboxState.selectedColor)
                let arrow = ArrowAnnotation(
                    startPoint: startPoint,
                    endPoint: endPoint,
                    color: safeColor,
                    lineWidth: toolboxState.lineWidth,
                    strokeEnabled: toolboxState.strokeEnabled
                )
                toolboxState.annotations.append(arrow)
                applyAnnotationsToImage()

                arrowTextStartPoint = startPoint
                arrowTextEndPoint = endPoint
                textPosition = startPoint
                textInput = ""
                showTextInput = true
            },
            onAnnotationChanged: {
                applyAnnotationsToImage()
                expandWindowForAnnotations()
            },
            onTextEdit: { index, textAnnotation in
                editingTextIndex = index
                textInput = textAnnotation.text
                textPosition = textAnnotation.position
                showTextInput = true
            },
            onDoubleClickEmpty: {
                showImage = false
            },
            onSelectionChanged: { [self] index in
                loadSelectedAnnotationAttributes(at: index)
            },
            onToolChanged: { [self] tool in
                toolbarController?.setTool(tool)
            },
            onTrimRequested: { [self] rect in
                performTrim(canvasRect: rect)
            },
            onCopyTrimRegion: { [self] rect in
                performCopyRegion(canvasRect: rect)
            },
            onCopyText: { [self] in
                copySelectedText()
            },
            imageDisplaySize: CGSize(
                width: screenshot.captureRegion?.width ?? screenshot.originalImage.size.width,
                height: screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
            )
        )
        .overlay {
            if toolboxState.selectedTool == .textSelection {
                textSelectionOverlay
            }
        }
    }

    // textSelectionOverlay / findCharIndex / mergeSelectionRects は
    // Mas/Views/Editor/EditorWindow+TextSelection.swift に移動済み

    private var closeButton: some View {
        Button(action: { closeWindow() }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(showImage ? .white : .gray)
                .padding(6)
                .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .position(x: 20, y: 20)
    }

    private var pinButton: some View {
        Button(action: {
            alwaysOnTop.toggle()
            parentWindow?.level = alwaysOnTop ? .floating : .normal
            if let window = parentWindow {
                NotificationCenter.default.post(name: .windowPinChanged, object: window)
            }
        }) {
            Image(systemName: alwaysOnTop ? "pin.fill" : "pin.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(showImage ? .white : .gray)
                .padding(6)
                .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .position(x: 48, y: 20)
    }

    private var inlineTextInput: some View {
        let offsetX = resizeState.originDelta.x
        let offsetY = resizeState.originDelta.y
        let fontSize = toolboxState.lineWidth * 5
        // NSView座標（左下原点）からSwiftUI座標（左上原点）に変換
        let canvasHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
        let swiftUIY = canvasHeight - textPosition.y
        // パディング分を補正（左パディング6pt）
        let paddingLeft: CGFloat = 6
        // テキストフィールド内のテキスト位置補正
        let textFieldInset: CGFloat = 2

        return HStack(spacing: 4) {
            TextField("テキストを入力", text: $textInput)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(toolboxState.selectedColor)
                .frame(minWidth: 100, alignment: .leading)
                .fixedSize()
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitTextInput()
                }

            Button(action: { submitTextInput() }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(NoHighlightButtonStyle())

            Button(action: { cancelTextInput() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(NoHighlightButtonStyle())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.9))
        .cornerRadius(6)
        .shadow(radius: 2)
        .fixedSize()
        .offset(
            x: textPosition.x + offsetX - paddingLeft - textFieldInset,
            y: swiftUIY + offsetY - fontSize * 0.3
        )
        .onExitCommand {
            cancelTextInput()
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private func submitTextInput() {
        if !textInput.isEmpty {
            let safeColor = Self.createIndependentNSColor(from: toolboxState.selectedColor)

            // 矢印文字ツールの場合：テキストを矢印の始点に追加
            if let arrowStart = arrowTextStartPoint, arrowTextEndPoint != nil {
                let textAnnotation = TextAnnotation(
                    position: arrowStart,
                    text: textInput,
                    font: .systemFont(ofSize: toolboxState.lineWidth * 5, weight: .medium),
                    color: safeColor,
                    strokeEnabled: toolboxState.strokeEnabled
                )
                toolboxState.annotations.append(textAnnotation)
                let newIndex = toolboxState.annotations.count - 1
                toolbarController?.setTool(.move)
                toolboxState.selectedAnnotationIndex = newIndex
                applyAnnotationsToImage()
            } else if let editIndex = editingTextIndex,
               editIndex < toolboxState.annotations.count,
               let existingText = toolboxState.annotations[editIndex] as? TextAnnotation {
                // 既存のテキストを編集
                existingText.text = textInput
                existingText.color = safeColor
                existingText.font = .systemFont(ofSize: toolboxState.lineWidth * 5, weight: .medium)
                existingText.strokeEnabled = toolboxState.strokeEnabled
            } else {
                // 新規テキストを追加
                let textAnnotation = TextAnnotation(
                    position: textPosition,
                    text: textInput,
                    font: .systemFont(ofSize: toolboxState.lineWidth * 5, weight: .medium),
                    color: safeColor,
                    strokeEnabled: toolboxState.strokeEnabled
                )
                toolboxState.annotations.append(textAnnotation)
                // テキスト追加後、選択モードに切り替え＆追加したオブジェクトを選択
                let newIndex = toolboxState.annotations.count - 1
                toolbarController?.setTool(.move)
                toolboxState.selectedAnnotationIndex = newIndex
            }
            // ドラッグ用画像を更新
            applyAnnotationsToImage()
        } else if let editIndex = editingTextIndex {
            // 空文字で確定した場合は削除
            if editIndex < toolboxState.annotations.count {
                toolboxState.annotations.remove(at: editIndex)
                applyAnnotationsToImage()
            }
        }
        textInput = ""
        showTextInput = false
        editingTextIndex = nil
        arrowTextStartPoint = nil
        arrowTextEndPoint = nil
    }

    /// SwiftUI ColorからSwiftUIへの参照を持たない独立したNSColorを作成
    private static func createIndependentNSColor(from color: Color) -> NSColor {
        // NSColor経由でRGB成分を抽出し、新しいNSColorを作成
        let nsColor = NSColor(color)

        // CIColorに変換してRGB成分を取得（SwiftUIとの依存関係を完全に断ち切る）
        guard let ciColor = CIColor(color: nsColor) else {
            return .systemRed
        }

        // 新しいNSColorを作成（完全に独立）
        return NSColor(
            calibratedRed: ciColor.red,
            green: ciColor.green,
            blue: ciColor.blue,
            alpha: ciColor.alpha
        )
    }

    private func cancelTextInput() {
        textInput = ""
        showTextInput = false
        editingTextIndex = nil
        arrowTextStartPoint = nil
        arrowTextEndPoint = nil
    }

    @ViewBuilder
    private func editModeToggle(geometry: GeometryProxy) -> some View {
        Button(action: {
            if editMode && !toolboxState.annotations.isEmpty && showImage {
                if screenshot.isGif {
                    // GIF: 全フレームにアノテーションを焼き込み
                    applyAnnotationsToGif()
                } else {
                    // 編集モード終了時にアノテーションを画像に適用
                    let annotationsCopy = toolboxState.annotations
                    let originalImage = screenshot.originalImage
                    let captureRegion = screenshot.captureRegion
                    let savedURL = screenshot.savedURL

                    DispatchQueue.main.async {
                        self.applyAnnotationsToImageSafe(
                            annotations: annotationsCopy,
                            originalImage: originalImage,
                            captureRegion: captureRegion,
                            savedURL: savedURL
                        )
                    }
                }
            }
            editMode.toggle()
        }) {
            Image(systemName: editMode ? "pencil.circle.fill" : "pencil.circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(editMode ? .blue : (showImage ? .white : .gray))
                .padding(8)
                .background(editMode ? Color.white.opacity(0.9) : (showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8)))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .position(x: 24, y: geometry.size.height - 24)
    }

    @ViewBuilder
    private func topRightButtons(geometry: GeometryProxy) -> some View {
        if screenshot.captureRegion != nil {
            HStack(spacing: 4) {
                if !showImage {
                    passThroughButton
                }
                captureActionButton
            }
            .position(x: geometry.size.width - (showImage ? 24 : 46), y: 20)
        }
    }

    private var captureActionButton: some View {
        Button(action: {
            executeCaptureAction(captureActionMode)
        }) {
            Image(systemName: captureActionMode.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(showImage ? .white : .gray)
                .padding(6)
                .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .contextMenu {
            ForEach(CaptureActionMode.allCases, id: \.self) { mode in
                Button {
                    captureActionMode = mode
                    executeCaptureAction(mode)
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        }
    }

    private func executeCaptureAction(_ mode: CaptureActionMode) {
        let rect = getCurrentWindowRect()
        switch mode {
        case .recapture:
            gifPlayerState?.pause()
            gifPlayerState = nil
            gifToolbarController?.close()
            gifToolbarController = nil
            onRecapture?(rect, parentWindow, true)
            showImage = true
            if passThroughEnabled {
                passThroughEnabled = false
                updatePassThrough()
            }
        case .gif:
            closeWindow()
            NotificationCenter.default.post(
                name: .startGifRecordingAtRegion,
                object: NSValue(rect: rect)
            )
        case .video:
            closeWindow()
            NotificationCenter.default.post(
                name: .startVideoRecordingAtRegion,
                object: NSValue(rect: rect)
            )
        }
    }

    private var passThroughButton: some View {
        Button(action: {
            passThroughEnabled.toggle()
            updatePassThrough()
        }) {
            Image(systemName: passThroughEnabled ? "hand.tap.fill" : "hand.tap")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(passThroughEnabled ? .blue : .gray)
                .padding(6)
                .background(Color.white.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    private func dragArea(geometry: GeometryProxy) -> some View {
        let screenshotRef = screenshot
        let toolboxRef = toolboxState
        return DraggableImageView(
            image: imageForDrag ?? screenshot.originalImage,
            showImage: showImage,
            gifURL: (screenshot.isGif || screenshot.isVideo) ? screenshot.savedURL : nil,
            imageProvider: {
                // ドラッグ開始時に最新のアノテーション付き画像をリアルタイムで生成
                if !toolboxRef.annotations.isEmpty, !screenshotRef.isGif, !screenshotRef.isVideo {
                    return EditorWindow.renderImageInBackground(
                        originalImage: screenshotRef.originalImage,
                        annotations: toolboxRef.annotations,
                        captureRegion: screenshotRef.captureRegion
                    )
                }
                return screenshotRef.originalImage
            },
            onDragSuccess: { [self] in
                // ドラッグ成功でウインドウが閉じる前にアノテーションを適用
                if !toolboxState.annotations.isEmpty {
                    applyAnnotations()
                }
                toolbarController?.close()
                shutterPanelController?.close()
                shutterPanelController = nil
            },
            onDragStart: { [self] in
                videoPlayerState?.pause()
                gifPlayerState?.pause()
            }
        )
        .frame(width: 32, height: 32)
        .position(x: geometry.size.width - 24, y: geometry.size.height - 24)
    }

    // expandWindowForAnnotations / applyAnnotationsToImage 系 / renderImageInBackground 系 / drawScaledAnnotationStatic は
    // Mas/Views/Editor/EditorWindow+AnnotationRendering.swift に移動済み


    func saveEditedImage(_ image: NSImage) {
        // 保存先URLが指定されていればそこに上書き、なければ新規作成
        let fileURL: URL
        if let existingURL = screenshot.savedURL {
            fileURL = existingURL
        } else {
            let saveFolder = UserDefaults.standard.string(forKey: "autoSaveFolder") ?? "~/Pictures/Mas"
            let expandedPath = NSString(string: saveFolder).expandingTildeInPath
            let folderURL = URL(fileURLWithPath: expandedPath)

            let formatString = UserDefaults.standard.string(forKey: "defaultFormat") ?? "PNG"
            let fileExtension = formatString.lowercased()

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Mas_\(dateFormatter.string(from: Date())).\(fileExtension)"
            fileURL = folderURL.appendingPathComponent(fileName)
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return }

        // ファイル拡張子から形式を判断
        let isJpeg = fileURL.pathExtension.lowercased() == "jpg" || fileURL.pathExtension.lowercased() == "jpeg"

        let imageData: Data?
        if isJpeg {
            let quality = UserDefaults.standard.double(forKey: "jpegQuality")
            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality > 0 ? quality : 0.9])
        } else {
            imageData = bitmapRep.representation(using: .png, properties: [:])
        }

        // バックグラウンドスレッドでファイル書き込み
        guard let data = imageData else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            try? data.write(to: fileURL)
        }
    }

    private func copyToClipboard() {
        // アノテーションがある場合はアノテーション付き画像をコピー
        if !toolboxState.annotations.isEmpty, !screenshot.isGif, !screenshot.isVideo {
            if let image = Self.renderImageInBackground(
                originalImage: screenshot.originalImage,
                annotations: toolboxState.annotations,
                captureRegion: screenshot.captureRegion
            ) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
                copiedToClipboard = true
                return
            }
        }
        if viewModel.copyToClipboard() {
            copiedToClipboard = true
        }
    }

    private func updatePassThrough() {
        onPassThroughChanged?(passThroughEnabled)
    }

    // performCopyRegion / performTrim / replaceWithTrimmedVideo / handleGifExportComplete は
    // Mas/Views/Editor/EditorWindow+Trim.swift に移動済み


    private func enterEditWithTool(_ tool: EditTool) {
        toolboxState.selectedTool = tool
        if !editMode {
            editMode = true
        }
    }

    private func setContentScale(_ scale: CGFloat) {
        contentScale = scale
        contentPanOffset = .zero
        guard let window = parentWindow else { return }
        let imageWidth = screenshot.captureRegion?.width ?? screenshot.originalImage.size.width
        let imageHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
        let scaledWidth = imageWidth * scale
        let scaledHeight = imageHeight * scale
        let currentFrame = window.frame

        // 画面の可視領域を取得
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 画面に収まる範囲でウィンドウサイズを調整
        let proposed = CGRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + (currentFrame.height - scaledHeight),
            width: scaledWidth,
            height: scaledHeight
        )
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        if clamped.size != currentFrame.size {
            window.setFrame(clamped, display: true, animate: true)
            if let resizableWindow = window as? ResizableWindow {
                resizableWindow.resizeState.reset()
            }
        }
    }

    private func closeWindow() {
        if editMode && !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }
        // ウィンドウ位置を保存（次回同じ場所に表示するため）
        saveCurrentWindowRect()
        toolboxState.annotations.removeAll()
        toolbarController?.close()
        shutterPanelController?.close()
        shutterPanelController = nil
        parentWindow?.close()
        NotificationCenter.default.post(name: .editorWindowClosed, object: nil)
    }

    private func saveCurrentWindowRect() {
        let rect = getCurrentWindowRect()
        guard rect.width > 0, rect.height > 0 else { return }
        let rectDict: [String: CGFloat] = [
            "x": rect.origin.x, "y": rect.origin.y,
            "width": rect.width, "height": rect.height
        ]
        UserDefaults.standard.set(rectDict, forKey: "lastCaptureRect")
    }

    private func openShutterMode(_ mode: ShutterTab) {
        guard let window = parentWindow else { return }
        // 既に開いている場合は一度閉じる
        if let controller = shutterPanelController {
            controller.close()
            shutterPanelController = nil
        }
        let controller = ShutterOptionsPanelController()
        controller.show(attachedTo: window, screenshot: screenshot, mode: mode) { [self] rect, parentWin in
                // GIFプレーヤーをクリア
                gifPlayerState?.pause()
                gifPlayerState = nil
                gifToolbarController?.close()
                gifToolbarController = nil
                onRecapture?(rect, parentWin, false)
                // 変化検知モード: 画像を非表示にして背後の変化が見えるようにする
                if shutterPanelController?.shutterService.activeMode == .changeDetection ||
                   shutterPanelController?.shutterService.activeMode == .interval ||
                   shutterPanelController?.shutterService.activeMode == .programmable {
                    showImage = false
                } else {
                    showImage = true
                }
                if passThroughEnabled {
                    passThroughEnabled = false
                    updatePassThrough()
                }
            }
            controller.onCloseRequested = { [self] in
                shutterPanelController?.close()
                shutterPanelController = nil
            }
            shutterPanelController = controller
    }

    // startTextRecognition / buildFlatChars / copySelectedText は
    // Mas/Views/Editor/EditorWindow+TextSelection.swift に移動済み
}



// AnnotationCanvasView / AnnotationCanvasDelegate / AnnotationCanvas は
// Mas/Views/Editor/AnnotationCanvas.swift に移動済み
