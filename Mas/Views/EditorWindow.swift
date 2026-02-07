import SwiftUI

// タップ時に色が変わらないButtonStyle
struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

// ドラッグ可能な領域（ウィンドウ移動をブロック）
struct DraggableImageView: NSViewRepresentable {
    let image: NSImage
    let showImage: Bool

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.image = image
        view.showImage = showImage
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.image = image
        nsView.showImage = showImage
        nsView.needsDisplay = true
    }
}

class DragSourceView: NSView {
    var image: NSImage?
    var showImage: Bool = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景（白で塗りつぶし）
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.white.setFill()
        bgPath.fill()

        // 外側の黒い縁取り
        let outerPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        outerPath.lineWidth = 1
        NSColor.black.setStroke()
        outerPath.stroke()

        // 内側のグレー縁取り
        let innerPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
        innerPath.lineWidth = 1
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        innerPath.stroke()

        // アイコン（黒で描画）
        if let symbolImage = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            let configuredImage = symbolImage.withSymbolConfiguration(config)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black]))
            let iconSize: CGFloat = 18
            let iconRect = NSRect(
                x: (bounds.width - iconSize) / 2,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            configuredImage?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    override func mouseDown(with event: NSEvent) {
    }

    override func mouseDragged(with event: NSEvent) {
        guard let image = image else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Mas_Screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)

        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

        let thumbnailSize = NSSize(width: 64, height: 64)
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 0.8)
        thumbnail.unlockFocus()

        draggingItem.setDraggingFrame(bounds, contents: thumbnail)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

extension DragSourceView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // ドラッグ開始時にウィンドウを非表示
        window?.orderOut(nil)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // ドラッグ成功時（コピー操作が行われた場合）
        if !operation.isEmpty {
            let closeOnDragSuccess = UserDefaults.standard.object(forKey: "closeOnDragSuccess") as? Bool ?? true
            if closeOnDragSuccess {
                window?.close()
                NotificationCenter.default.post(name: .editorWindowClosed, object: nil)
                return
            }
        }
        // ドラッグ終了時にウィンドウを再表示
        window?.makeKeyAndOrderFront(nil)
    }
}

// 編集ツールの種類
enum EditTool: String, CaseIterable {
    case move = "移動"
    case pen = "ペン"
    case highlight = "マーカー"
    case arrow = "矢印"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "文字"
    case mosaic = "ぼかし"
    case trim = "トリミング"

    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .mosaic: return "drop.fill"
        case .trim: return "crop"
        }
    }
}

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @ObservedObject var toolboxState: ToolboxState
    @ObservedObject var resizeState: WindowResizeState
    @State private var copiedToClipboard = false
    @State private var showImage: Bool
    @State private var passThroughEnabled = false
    @State private var editMode = false
    @State private var currentAnnotation: (any Annotation)?
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero
    @FocusState private var isTextFieldFocused: Bool
    @State private var toolbarController: FloatingToolbarWindowController?
    @State private var isLoadingAnnotationAttributes = false
    @State private var imageForDrag: NSImage?  // アノテーション付きドラッグ用画像
    @State private var editingTextIndex: Int?  // 編集中のテキストアノテーションのインデックス

    let onRecapture: ((CGRect, NSWindow?) -> Void)?
    let onPassThroughChanged: ((Bool) -> Void)?
    weak var parentWindow: NSWindow?

    init(screenshot: Screenshot, resizeState: WindowResizeState, toolboxState: ToolboxState, parentWindow: NSWindow? = nil, onRecapture: ((CGRect, NSWindow?) -> Void)? = nil, onPassThroughChanged: ((Bool) -> Void)? = nil, showImageInitially: Bool = true) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.resizeState = resizeState
        self.toolboxState = toolboxState
        self.parentWindow = parentWindow
        self.onRecapture = onRecapture
        self.onPassThroughChanged = onPassThroughChanged
        _showImage = State(initialValue: showImageInitially)
    }

    private func getCurrentWindowRect() -> CGRect {
        guard let window = parentWindow else {
            return screenshot.captureRegion ?? .zero
        }
        let frame = window.frame
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let rect = CGRect(
            x: frame.origin.x,
            y: screenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        return rect
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                imageContent
                closeButton
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
        .contextMenu {
            Button("閉じる") { closeWindow() }
            Divider()
            Button("クリップボードにコピー") { copyToClipboard() }
        }
        .onAppear {
            toolbarController = FloatingToolbarWindowController()
        }
        .onDisappear {
            toolbarController?.close()
        }
        .onChange(of: editMode) { newValue in
            if newValue {
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
            if showTextInput && newTool != .text {
                cancelTextInput()
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
                } else {
                    Color.clear
                        .frame(width: imageWidth, height: imageHeight)
                }
                // 編集モード中、またはアノテーションがある場合にcanvasを表示
                if editMode || !toolboxState.annotations.isEmpty {
                    annotationCanvas
                }
            }
            .offset(x: offsetX, y: offsetY)
        }
        .clipped()
    }

    @ViewBuilder
    private var screenshotImage: some View {
        if let region = screenshot.captureRegion {
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
            sourceImage: screenshot.originalImage,
            isEditing: editMode,
            showImage: showImage,
            toolboxState: toolboxState,
            onTextTap: { position in
                textPosition = position
                showTextInput = true
            },
            onAnnotationChanged: {
                applyAnnotationsToImage()
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
            }
        )
        .frame(
            width: screenshot.captureRegion?.width ?? screenshot.originalImage.size.width,
            height: screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
        )
    }

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

            if let editIndex = editingTextIndex,
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
    }

    @ViewBuilder
    private func editModeToggle(geometry: GeometryProxy) -> some View {
        Button(action: {
            if editMode && !toolboxState.annotations.isEmpty && showImage {
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
                recaptureButton
            }
            .position(x: geometry.size.width - (showImage ? 20 : 36), y: 20)
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

    private var recaptureButton: some View {
        Button(action: {
            let rect = getCurrentWindowRect()
            onRecapture?(rect, parentWindow)
            showImage = true
            if passThroughEnabled {
                passThroughEnabled = false
                updatePassThrough()
            }
        }) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(showImage ? .white : .gray)
                .padding(6)
                .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    private func dragArea(geometry: GeometryProxy) -> some View {
        DraggableImageView(image: imageForDrag ?? screenshot.originalImage, showImage: showImage)
            .frame(width: 32, height: 32)
            .position(x: geometry.size.width - 24, y: geometry.size.height - 24)
    }

    // アノテーションを画像に反映して自動保存（アノテーションは保持）
    private func applyAnnotationsToImage() {
        guard !toolboxState.annotations.isEmpty else { return }

        // 同期的に画像をレンダリング（アノテーションの参照が有効な間に処理）
        let renderedImage = Self.renderImageInBackground(
            originalImage: screenshot.originalImage,
            annotations: toolboxState.annotations,
            captureRegion: screenshot.captureRegion
        )

        guard let image = renderedImage else { return }

        // ドラッグ用画像を更新
        imageForDrag = image

        let savedURL = screenshot.savedURL

        // バックグラウンドで保存処理
        DispatchQueue.global(qos: .userInitiated).async {
            let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
            if autoSaveEnabled {
                Self.saveImageToFile(image, url: savedURL)
            }
        }

        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    // SwiftUI状態に依存しない安全なレンダリング処理
    private func applyAnnotationsToImageSafe(annotations: [any Annotation], originalImage: NSImage, captureRegion: CGRect?, savedURL: URL?) {
        guard !annotations.isEmpty else { return }

        let renderedImage = Self.renderImageInBackground(
            originalImage: originalImage,
            annotations: annotations,
            captureRegion: captureRegion
        )

        guard let image = renderedImage else { return }

        // screenshot.originalImageを更新（ドラッグ時に使用される）
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            screenshot.updateImage(cgImage)
        }

        // アノテーションをクリア（画像に適用済み）
        toolboxState.annotations.removeAll()

        // ドラッグ用一時画像をクリア（originalImageが更新されたため不要）
        imageForDrag = nil

        // バックグラウンドで保存処理
        DispatchQueue.global(qos: .userInitiated).async {
            let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
            if autoSaveEnabled {
                Self.saveImageToFile(image, url: savedURL)
            }
        }

        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    // バックグラウンドで画像をレンダリング
    private static func renderImageInBackground(originalImage: NSImage, annotations: [any Annotation], captureRegion: CGRect?) -> NSImage? {
        let imageSize = originalImage.size
        let canvasSize = captureRegion?.size ?? imageSize
        let scale = imageSize.width / canvasSize.width

        // モザイク効果を適用
        var baseImage = originalImage
        for annotation in annotations {
            if let mosaic = annotation as? MosaicAnnotation {
                let scaledRect = CGRect(
                    x: mosaic.rect.origin.x * scale,
                    y: mosaic.rect.origin.y * scale,
                    width: mosaic.rect.width * scale,
                    height: mosaic.rect.height * scale
                )
                let scaledMosaic = MosaicAnnotation(
                    rect: scaledRect,
                    pixelSize: max(Int(CGFloat(mosaic.pixelSize) * scale), 5)
                )
                baseImage = scaledMosaic.applyBlurToImage(baseImage, in: scaledRect)
            }
        }

        // NSImageのlockFocusを使用して描画（より確実）
        let resultImage = NSImage(size: imageSize)
        resultImage.lockFocus()

        // モザイク適用済み画像を描画
        baseImage.draw(in: NSRect(origin: .zero, size: imageSize))

        // その他のアノテーションを描画
        for annotation in annotations {
            if !(annotation is MosaicAnnotation) {
                Self.drawScaledAnnotationStatic(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height)
            }
        }

        resultImage.unlockFocus()
        return resultImage
    }

    // ファイルに保存（バックグラウンド用）
    private static func saveImageToFile(_ image: NSImage, url: URL?) {
        // 保存先URLが指定されていればそこに上書き、なければ新規作成
        let fileURL: URL
        if let existingURL = url {
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

        try? imageData?.write(to: fileURL)
    }

    // 画像とアノテーションを合成した画像を生成
    private func renderImageWithAnnotations() -> NSImage {
        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize
        let scale = imageSize.width / canvasSize.width

        // まずモザイク効果を適用
        var baseImage = screenshot.originalImage
        for annotation in toolboxState.annotations {
            if let mosaic = annotation as? MosaicAnnotation {
                let scaledRect = CGRect(
                    x: mosaic.rect.origin.x * scale,
                    y: mosaic.rect.origin.y * scale,
                    width: mosaic.rect.width * scale,
                    height: mosaic.rect.height * scale
                )
                let scaledMosaic = MosaicAnnotation(
                    rect: scaledRect,
                    pixelSize: max(Int(CGFloat(mosaic.pixelSize) * scale), 5)
                )
                baseImage = scaledMosaic.applyBlurToImage(baseImage, in: scaledRect)
            }
        }

        let newImage = NSImage(size: imageSize)
        newImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: imageSize))

        for annotation in toolboxState.annotations {
            if !(annotation is MosaicAnnotation) {
                Self.drawScaledAnnotationStatic(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height)
            }
        }

        newImage.unlockFocus()
        return newImage
    }

    private func applyAnnotations() {
        guard !toolboxState.annotations.isEmpty else { return }

        let newImage = renderImageWithAnnotations()

        if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            screenshot.updateImage(cgImage)
        }

        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([newImage])
        }

        let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
        if autoSaveEnabled {
            saveEditedImage(newImage)
        }

        toolboxState.annotations.removeAll()
    }

    private static func drawScaledAnnotationStatic(_ annotation: any Annotation, scale: CGFloat, imageHeight: CGFloat, canvasHeight: CGFloat) {
        // 単純にスケーリングのみ（NSViewとNSImageは同じ左下原点座標系）
        if let arrow = annotation as? ArrowAnnotation {
            let startPoint = CGPoint(
                x: arrow.startPoint.x * scale,
                y: arrow.startPoint.y * scale
            )
            let endPoint = CGPoint(
                x: arrow.endPoint.x * scale,
                y: arrow.endPoint.y * scale
            )
            let scaledArrow = ArrowAnnotation(
                startPoint: startPoint,
                endPoint: endPoint,
                color: arrow.color.copy() as! NSColor,
                lineWidth: arrow.lineWidth * scale,
                strokeEnabled: arrow.strokeEnabled
            )
            scaledArrow.draw(in: .zero)
        } else if let rect = annotation as? RectAnnotation {
            let scaledRect = CGRect(
                x: rect.rect.origin.x * scale,
                y: rect.rect.origin.y * scale,
                width: rect.rect.width * scale,
                height: rect.rect.height * scale
            )
            let scaledAnnotation = RectAnnotation(
                rect: scaledRect,
                color: rect.color.copy() as! NSColor,
                lineWidth: rect.lineWidth * scale,
                strokeEnabled: rect.strokeEnabled
            )
            scaledAnnotation.draw(in: .zero)
        } else if let ellipse = annotation as? EllipseAnnotation {
            let scaledRect = CGRect(
                x: ellipse.rect.origin.x * scale,
                y: ellipse.rect.origin.y * scale,
                width: ellipse.rect.width * scale,
                height: ellipse.rect.height * scale
            )
            let scaledAnnotation = EllipseAnnotation(
                rect: scaledRect,
                color: ellipse.color.copy() as! NSColor,
                lineWidth: ellipse.lineWidth * scale,
                strokeEnabled: ellipse.strokeEnabled
            )
            scaledAnnotation.draw(in: .zero)
        } else if let text = annotation as? TextAnnotation {
            let scaledFont = NSFont.systemFont(ofSize: text.font.pointSize * scale, weight: .medium)
            let scaledPosition = CGPoint(
                x: text.position.x * scale,
                y: text.position.y * scale
            )
            let scaledAnnotation = TextAnnotation(
                position: scaledPosition,
                text: String(text.text),
                font: scaledFont,
                color: text.color.copy() as! NSColor,
                strokeEnabled: text.strokeEnabled
            )
            scaledAnnotation.draw(in: .zero)
        } else if let highlight = annotation as? HighlightAnnotation {
            let scaledRect = CGRect(
                x: highlight.rect.origin.x * scale,
                y: highlight.rect.origin.y * scale,
                width: highlight.rect.width * scale,
                height: highlight.rect.height * scale
            )
            let scaledAnnotation = HighlightAnnotation(
                rect: scaledRect,
                color: highlight.color.copy() as! NSColor
            )
            scaledAnnotation.draw(in: .zero)
        } else if let mosaic = annotation as? MosaicAnnotation {
            let scaledRect = CGRect(
                x: mosaic.rect.origin.x * scale,
                y: mosaic.rect.origin.y * scale,
                width: mosaic.rect.width * scale,
                height: mosaic.rect.height * scale
            )
            let scaledAnnotation = MosaicAnnotation(
                rect: scaledRect,
                pixelSize: Int(CGFloat(mosaic.pixelSize) * scale)
            )
            scaledAnnotation.draw(in: .zero)
        } else if let freehand = annotation as? FreehandAnnotation {
            let scaledPoints = freehand.points.map { point in
                CGPoint(x: point.x * scale, y: point.y * scale)
            }
            let scaledAnnotation = FreehandAnnotation(
                points: scaledPoints,
                color: freehand.color.copy() as! NSColor,
                lineWidth: freehand.lineWidth * scale,
                isHighlighter: freehand.isHighlighter,
                strokeEnabled: freehand.strokeEnabled
            )
            scaledAnnotation.draw(in: .zero)
        }
    }

    private func saveEditedImage(_ image: NSImage) {
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
        if viewModel.copyToClipboard() {
            copiedToClipboard = true
        }
    }

    private func updatePassThrough() {
        onPassThroughChanged?(passThroughEnabled)
    }

    private func performTrim(canvasRect: CGRect) {
        // 1. 既存アノテーションがあれば先に画像に焼き込み
        if !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }

        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let scale = imageSize.width / canvasSize.width

        // 2. キャンバス座標→ピクセル座標に変換
        // AnnotationCanvas は左下原点、CGImage は左上原点
        let pixelX = canvasRect.origin.x * scale
        let pixelY = (canvasSize.height - canvasRect.origin.y - canvasRect.height) * scale
        let pixelWidth = canvasRect.width * scale
        let pixelHeight = canvasRect.height * scale

        // 画像範囲内にclamp
        let imageBounds = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
            .integral
            .intersection(imageBounds)

        guard cropRect.width > 0, cropRect.height > 0 else { return }

        // 3. CGImage.cropping(to:) で切り取り
        guard let cgImage = screenshot.originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return }

        // 4. screenshot.updateImage() で画像更新
        screenshot.updateImage(croppedCGImage)

        // 5. captureRegion を新サイズに更新（トリミング後のキャンバスサイズ）
        let newCanvasWidth = cropRect.width / scale
        let newCanvasHeight = cropRect.height / scale
        let oldRegion = screenshot.captureRegion ?? CGRect(origin: .zero, size: imageSize)
        screenshot.captureRegion = CGRect(
            x: oldRegion.origin.x,
            y: oldRegion.origin.y,
            width: newCanvasWidth,
            height: newCanvasHeight
        )

        // 6. ウィンドウをトリミング範囲のスクリーン位置に移動＆リサイズ
        // canvasRect.originはキャンバス座標（左下原点）でのトリミング範囲の左下
        // originDelta: SwiftUIの.offset()によるキャンバスのシフト量
        let dx = resizeState.originDelta.x
        let dy = resizeState.originDelta.y
        if let window = parentWindow {
            let oldFrame = window.frame
            // キャンバスの左下のスクリーン座標 = ウィンドウ上端 - dy - canvasHeight
            // トリミング範囲の左下のスクリーン座標:
            let screenX = oldFrame.origin.x + dx + canvasRect.origin.x
            let screenY = oldFrame.origin.y + oldFrame.height - dy - canvasSize.height + canvasRect.origin.y
            let newFrame = NSRect(
                x: screenX,
                y: screenY,
                width: newCanvasWidth,
                height: newCanvasHeight
            )
            window.setFrame(newFrame, display: true)
        }
        resizeState.reset()

        // 7. 自動保存・クリップボードコピー（設定に応じて）
        let newImage = screenshot.originalImage
        let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
        if autoSaveEnabled {
            saveEditedImage(newImage)
        }
        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([newImage])
        }

        // ドラッグ用画像をクリア
        imageForDrag = nil

        // 8. ツールを .move に戻す
        toolboxState.selectedTool = .move
        toolbarController?.setTool(.move)
    }

    private func closeWindow() {
        if editMode && !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }
        toolboxState.annotations.removeAll()
        toolbarController?.close()
        parentWindow?.close()
        NotificationCenter.default.post(name: .editorWindowClosed, object: nil)
    }
}


// 注釈描画キャンバス
struct AnnotationCanvasView: NSViewRepresentable {
    @Binding var annotations: [any Annotation]
    @Binding var currentAnnotation: (any Annotation)?
    let selectedTool: EditTool
    let selectedColor: NSColor
    let lineWidth: CGFloat
    let strokeEnabled: Bool
    let sourceImage: NSImage
    let isEditing: Bool
    let showImage: Bool
    let toolboxState: ToolboxState
    let onTextTap: (CGPoint) -> Void
    let onAnnotationChanged: () -> Void
    let onTextEdit: ((Int, TextAnnotation) -> Void)?
    let onDoubleClickEmpty: (() -> Void)?
    let onSelectionChanged: ((Int?) -> Void)?
    let onToolChanged: ((EditTool) -> Void)?
    var onTrimRequested: ((CGRect) -> Void)?

    func makeNSView(context: Context) -> AnnotationCanvas {
        let canvas = AnnotationCanvas()
        canvas.delegate = context.coordinator
        canvas.sourceImage = sourceImage
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateNSView(_ nsView: AnnotationCanvas, context: Context) {
        // ツール変更時にトリミング選択範囲をクリア
        if nsView.selectedTool != selectedTool {
            nsView.trimRect = nil
        }
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.selectedTool = selectedTool
        nsView.selectedColor = selectedColor
        nsView.lineWidth = lineWidth
        nsView.strokeEnabled = strokeEnabled
        nsView.sourceImage = sourceImage
        nsView.isEditing = isEditing
        nsView.showImage = showImage
        // 編集モード終了時に選択をクリア
        if !isEditing {
            nsView.clearSelection()
            // 状態変更を次のRunLoopサイクルに遅延（クラッシュ防止）
            if toolboxState.selectedAnnotationIndex != nil {
                let state = toolboxState
                DispatchQueue.main.async {
                    state.selectedAnnotationIndex = nil
                }
            }
        } else {
            // ToolboxStateの選択状態をCanvasに同期
            nsView.setSelectedIndex(toolboxState.selectedAnnotationIndex)
        }
        // ウィンドウフレームを更新
        nsView.updateWindowFrame()
        // リアルタイムキャプチャモードのタイマー制御
        nsView.updateRefreshTimer(hasMosaicAnnotations: annotations.contains { $0 is MosaicAnnotation })
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AnnotationCanvasDelegate {
        var parent: AnnotationCanvasView
        weak var canvas: AnnotationCanvas?

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func annotationAdded(_ annotation: any Annotation) {
            // モザイクは常に後ろ（配列の先頭）に追加
            let newIndex: Int
            if annotation is MosaicAnnotation {
                parent.annotations.insert(annotation, at: 0)
                newIndex = 0
            } else {
                parent.annotations.append(annotation)
                newIndex = parent.annotations.count - 1
            }
            // 直接canvasの配列も更新（同期問題を回避）
            canvas?.annotations = parent.annotations
            canvas?.needsDisplay = true

            parent.currentAnnotation = nil
            parent.onAnnotationChanged()

            // ペン・マーカー以外の場合のみ選択モードに切り替え
            if !(annotation is FreehandAnnotation) {
                parent.onToolChanged?(.move)
                parent.toolboxState.selectedAnnotationIndex = newIndex
                canvas?.setSelectedIndex(newIndex)
                canvas?.needsDisplay = true
            }
        }

        func currentAnnotationUpdated(_ annotation: (any Annotation)?) {
            parent.currentAnnotation = annotation
        }

        func textTapped(at position: CGPoint) {
            parent.onTextTap(position)
        }

        func annotationMoved() {
            // canvasの配列を親に反映
            if let canvasAnnotations = canvas?.annotations {
                parent.annotations = canvasAnnotations
            }
            parent.onAnnotationChanged()
        }

        func selectionChanged(_ index: Int?) {
            parent.toolboxState.selectedAnnotationIndex = index
            // 選択時にアノテーションの属性をツールボックスに読み込み
            parent.onSelectionChanged?(index)
        }

        func deleteSelectedAnnotation() {
            guard let index = parent.toolboxState.selectedAnnotationIndex,
                  index < parent.annotations.count else { return }
            parent.annotations.remove(at: index)
            canvas?.annotations = parent.annotations

            // 削除後に次のアノテーションを自動選択
            let newIndex: Int?
            if parent.annotations.isEmpty {
                newIndex = nil
            } else if index < parent.annotations.count {
                // 同じ位置に次のアノテーションがあればそれを選択
                newIndex = index
            } else {
                // 最後の要素だった場合は一つ前を選択
                newIndex = parent.annotations.count - 1
            }

            canvas?.setSelectedIndex(newIndex)
            parent.toolboxState.selectedAnnotationIndex = newIndex
            canvas?.needsDisplay = true
            parent.onAnnotationChanged()
        }

        func editTextAnnotation(at index: Int, annotation: TextAnnotation) {
            parent.onTextEdit?(index, annotation)
        }

        func doubleClickedOnEmpty() {
            parent.onDoubleClickEmpty?()
        }

        func trimRequested(rect: CGRect) {
            parent.onTrimRequested?(rect)
        }
    }
}

protocol AnnotationCanvasDelegate: AnyObject {
    func annotationAdded(_ annotation: any Annotation)
    func currentAnnotationUpdated(_ annotation: (any Annotation)?)
    func textTapped(at position: CGPoint)
    func annotationMoved()
    func selectionChanged(_ index: Int?)
    func deleteSelectedAnnotation()
    func editTextAnnotation(at index: Int, annotation: TextAnnotation)
    func doubleClickedOnEmpty()
    func trimRequested(rect: CGRect)
}

// リサイズハンドルの位置
enum ResizeHandle {
    case none
    case topLeft, topRight, bottomLeft, bottomRight
    case startPoint, endPoint  // 矢印用
}

class AnnotationCanvas: NSView {
    weak var delegate: AnnotationCanvasDelegate?
    var annotations: [any Annotation] = []
    var currentAnnotation: (any Annotation)?
    var selectedTool: EditTool = .arrow
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 3
    var strokeEnabled: Bool = true
    var sourceImage: NSImage?
    var isEditing: Bool = false
    var showImage: Bool = true
    private var dragStart: CGPoint?
    private var selectedAnnotationIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMoveAnnotation: Bool = false
    private var windowFrame: CGRect = .zero
    private var refreshTimer: Timer?
    private var activeResizeHandle: ResizeHandle = .none
    private var isResizing: Bool = false
    var trimRect: CGRect?
    private var trimDragStart: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override var mouseDownCanMoveWindow: Bool { !isEditing }

    func clearSelection() {
        selectedAnnotationIndex = nil
    }

    func setSelectedIndex(_ index: Int?) {
        selectedAnnotationIndex = index
    }

    func updateWindowFrame() {
        if let windowFrame = window?.frame {
            self.windowFrame = windowFrame
        }
    }

    private var needsRefreshTimer: Bool = false

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        // 約30fpsでリアルタイム更新
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.needsRefreshTimer else { return }
            // モザイクのキャッシュをクリアして再描画
            for annotation in self.annotations {
                if let mosaic = annotation as? MosaicAnnotation {
                    mosaic.clearCache()
                }
            }
            self.needsDisplay = true
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshTimer(hasMosaicAnnotations: Bool) {
        needsRefreshTimer = !showImage && hasMosaicAnnotations
        if needsRefreshTimer {
            startRefreshTimer()
        }
        // タイマーは停止しない（再開コストが高いため）
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 編集モードでない場合はヒットテストを無効にしてイベントを通過させる
        if !isEditing {
            return nil
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // ウィンドウフレームを更新
        updateWindowFrame()
        let winNum = window?.windowNumber ?? 0

        // 配列の順序通りに描画（インデックス0が最背面、最後が最前面）
        for (index, annotation) in annotations.enumerated() {
            // モザイクアノテーションの場合、リアルタイムキャプチャモードを設定
            if let mosaic = annotation as? MosaicAnnotation {
                mosaic.useRealTimeCapture = !showImage
                mosaic.windowFrame = windowFrame
                mosaic.windowNumber = winNum
                mosaic.canvasSize = bounds.size
            }
            annotation.draw(in: bounds)
            // 編集モード中の移動モードのみバウンディングボックスを描画
            if isEditing && selectedTool == .move {
                let isSelected = index == selectedAnnotationIndex
                drawBoundingBox(for: annotation, isSelected: isSelected)
            }
        }

        // 現在描画中のアノテーション
        if let current = currentAnnotation {
            if let mosaic = current as? MosaicAnnotation {
                mosaic.useRealTimeCapture = !showImage
                mosaic.windowFrame = windowFrame
                mosaic.windowNumber = winNum
                mosaic.canvasSize = bounds.size
            }
            current.draw(in: bounds)
        }

        // トリミング選択範囲の描画
        if selectedTool == .trim, let trimRect = trimRect {
            drawTrimOverlay(trimRect: trimRect)
        }
    }

    private func drawTrimOverlay(trimRect: CGRect) {
        // 選択範囲外を半透明黒でオーバーレイ
        let overlayPath = NSBezierPath(rect: bounds)
        overlayPath.appendRect(trimRect)
        overlayPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        overlayPath.fill()

        // 選択範囲に白枠
        let borderPath = NSBezierPath(rect: trimRect)
        borderPath.lineWidth = 1.5
        NSColor.white.setStroke()
        borderPath.stroke()

        // 選択範囲に青点線
        let dashPath = NSBezierPath(rect: trimRect)
        dashPath.lineWidth = 1.5
        let dashPattern: [CGFloat] = [6, 4]
        dashPath.setLineDash(dashPattern, count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        dashPath.stroke()

        // 右下にサイズ表示
        let width = Int(trimRect.width)
        let height = Int(trimRect.height)
        let sizeText = "\(width) x \(height)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let textSize = sizeText.size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: trimRect.maxX - textSize.width - 4,
            y: trimRect.minY + 4
        )
        sizeText.draw(at: textPoint, withAttributes: attributes)
    }

    private func drawBoundingBox(for annotation: any Annotation, isSelected: Bool) {
        let highlightPath = NSBezierPath()
        highlightPath.lineWidth = isSelected ? 2 : 1

        var boundingRect: CGRect = .zero

        if let arrow = annotation as? ArrowAnnotation {
            boundingRect = arrow.boundingRect()
            highlightPath.appendRect(boundingRect)
        } else if let rect = annotation as? RectAnnotation {
            boundingRect = rect.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let ellipse = annotation as? EllipseAnnotation {
            boundingRect = ellipse.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let text = annotation as? TextAnnotation {
            let size = text.textSize()
            let drawY = text.position.y - text.font.ascender
            boundingRect = CGRect(origin: CGPoint(x: text.position.x - 3, y: drawY - 3), size: CGSize(width: size.width + 6, height: size.height + 6))
            highlightPath.appendRect(boundingRect)
        } else if let mosaic = annotation as? MosaicAnnotation {
            boundingRect = mosaic.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let freehand = annotation as? FreehandAnnotation {
            boundingRect = freehand.boundingRect()
            highlightPath.appendRect(boundingRect)
        } else if let highlight = annotation as? HighlightAnnotation {
            boundingRect = highlight.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        }

        let dashPattern: [CGFloat] = [4, 4]
        highlightPath.setLineDash(dashPattern, count: 2, phase: 0)

        if isSelected {
            NSColor.systemBlue.setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.6).setStroke()
        }
        highlightPath.stroke()

        // 選択中のアノテーションにリサイズハンドルを描画
        if isSelected {
            if let arrow = annotation as? ArrowAnnotation {
                // 矢印は始点と終点にハンドル
                drawResizeHandle(at: arrow.startPoint)
                drawResizeHandle(at: arrow.endPoint)
            } else if annotation is RectAnnotation || annotation is EllipseAnnotation || annotation is MosaicAnnotation {
                // 四角形系は四隅にハンドル
                drawResizeHandle(at: CGPoint(x: boundingRect.minX, y: boundingRect.minY))
                drawResizeHandle(at: CGPoint(x: boundingRect.maxX, y: boundingRect.minY))
                drawResizeHandle(at: CGPoint(x: boundingRect.minX, y: boundingRect.maxY))
                drawResizeHandle(at: CGPoint(x: boundingRect.maxX, y: boundingRect.maxY))
            }
        }
    }

    private func drawResizeHandle(at point: CGPoint) {
        let handleSize: CGFloat = 8
        let handleRect = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2, width: handleSize, height: handleSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(ovalIn: handleRect)
        path.lineWidth = 1.5
        path.stroke()
    }

    /// リサイズハンドルのヒットテスト
    private func hitTestResizeHandle(at point: CGPoint) -> ResizeHandle {
        guard let index = selectedAnnotationIndex, index < annotations.count else {
            return .none
        }

        let handleSize: CGFloat = 12  // ヒットエリアは少し大きめに
        let annotation = annotations[index]

        if let arrow = annotation as? ArrowAnnotation {
            // 矢印は始点と終点をチェック
            if CGRect(x: arrow.startPoint.x - handleSize / 2, y: arrow.startPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .startPoint
            }
            if CGRect(x: arrow.endPoint.x - handleSize / 2, y: arrow.endPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .endPoint
            }
        } else if let rect = annotation as? RectAnnotation {
            return hitTestCorners(rect: rect.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        } else if let ellipse = annotation as? EllipseAnnotation {
            return hitTestCorners(rect: ellipse.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        } else if let mosaic = annotation as? MosaicAnnotation {
            return hitTestCorners(rect: mosaic.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        }

        return .none
    }

    /// 四隅のハンドルをヒットテスト
    private func hitTestCorners(rect: CGRect, point: CGPoint, handleSize: CGFloat) -> ResizeHandle {
        let corners: [(CGPoint, ResizeHandle)] = [
            (CGPoint(x: rect.minX, y: rect.minY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .bottomRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .topLeft),
            (CGPoint(x: rect.maxX, y: rect.maxY), .topRight)
        ]

        for (cornerPoint, handle) in corners {
            let hitRect = CGRect(x: cornerPoint.x - handleSize / 2, y: cornerPoint.y - handleSize / 2, width: handleSize, height: handleSize)
            if hitRect.contains(point) {
                return handle
            }
        }
        return .none
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }

        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        lastDragPoint = point

        // ダブルクリック処理
        if event.clickCount == 2 {
            // 移動モードでテキストアノテーション上ならテキスト編集
            if selectedTool == .move {
                for (index, annotation) in annotations.enumerated().reversed() {
                    if let textAnnotation = annotation as? TextAnnotation,
                       textAnnotation.contains(point: point) {
                        delegate?.editTextAnnotation(at: index, annotation: textAnnotation)
                        return
                    }
                }
            }
            // 空白部分のダブルクリック - 画像を非表示
            let hitAnnotation = annotations.contains { $0.contains(point: point) }
            if !hitAnnotation {
                delegate?.doubleClickedOnEmpty()
                return
            }
        }

        // トリミングモードの場合
        if selectedTool == .trim {
            trimDragStart = point
            trimRect = nil
            needsDisplay = true
            return
        }

        // 移動モードの場合
        if selectedTool == .move {
            // まずリサイズハンドルのヒットテストを行う
            let handle = hitTestResizeHandle(at: point)
            if handle != .none {
                activeResizeHandle = handle
                isResizing = true
                return
            }

            // 前の選択状態を記録（インデックスが有効な場合のみ）
            let previousSelectedIndex = selectedAnnotationIndex
            let previousWasMosaic: Bool = {
                guard let index = previousSelectedIndex, index < annotations.count else { return false }
                return annotations[index] is MosaicAnnotation
            }()

            // クリックした位置にあるアノテーションを探す（配列のインデックス順）
            let clickedIndices = annotations.enumerated()
                .filter { $0.element.contains(point: point) }
                .map { $0.offset }

            if clickedIndices.isEmpty {
                // 何もない場所をクリック - 選択解除してウィンドウドラッグ開始
                // ぼかしが選択されていたら最背面に移動
                if previousWasMosaic, let prevIndex = previousSelectedIndex {
                    moveMosaicToBack(at: prevIndex)
                }
                selectedAnnotationIndex = nil
                delegate?.selectionChanged(nil)
                needsDisplay = true
                // ウィンドウドラッグを開始
                window?.performDrag(with: event)
                return
            } else if let currentIndex = previousSelectedIndex, clickedIndices.contains(currentIndex) {
                // 選択中のオブジェクトがクリックされた場合 - サイクル選択
                // 現在選択中の要素を後ろに移動（ただしぼかしより後ろには行かない）
                let movedAnnotation = annotations.remove(at: currentIndex)

                if movedAnnotation is MosaicAnnotation {
                    // ぼかしの場合は最背面（インデックス0）に移動
                    annotations.insert(movedAnnotation, at: 0)
                } else {
                    // ぼかし以外の場合、ぼかしの直後に移動
                    let mosaicCount = annotations.filter { $0 is MosaicAnnotation }.count
                    annotations.insert(movedAnnotation, at: mosaicCount)
                }

                // インデックスを再計算してクリック位置のオブジェクトを探す
                let newClickedIndices = annotations.enumerated()
                    .filter { $0.element.contains(point: point) }
                    .map { $0.offset }

                // 一番上のオブジェクトを選択
                if let topIndex = newClickedIndices.last {
                    selectedAnnotationIndex = topIndex
                    // ぼかしが選択された場合は最前面に移動
                    if annotations[topIndex] is MosaicAnnotation {
                        moveMosaicToFront(at: topIndex)
                    }
                } else {
                    selectedAnnotationIndex = nil
                }

                // 配列が変更されたのでcanvasを更新
                delegate?.annotationMoved()
            } else {
                // 新しいオブジェクトを選択
                // 前に選択していたぼかしは最背面に移動
                if previousWasMosaic, let prevIndex = previousSelectedIndex {
                    moveMosaicToBack(at: prevIndex)
                }

                // 一番上のオブジェクトを選択（インデックスが最大のもの）
                if let topIndex = clickedIndices.last {
                    selectedAnnotationIndex = topIndex
                    // ぼかしが選択された場合は最前面に移動
                    if annotations[topIndex] is MosaicAnnotation {
                        moveMosaicToFront(at: topIndex)
                    }
                }
            }
            delegate?.selectionChanged(selectedAnnotationIndex)
            needsDisplay = true
            return
        }

        if selectedTool == .text {
            delegate?.textTapped(at: point)
            return
        }

        // 色を完全にコピーして使用（SwiftUI状態への参照を断ち切る）
        let safeColor = (selectedColor.copy() as? NSColor) ?? .systemRed

        switch selectedTool {
        case .move:
            break
        case .pen:
            currentAnnotation = FreehandAnnotation(points: [point], color: safeColor, lineWidth: lineWidth, isHighlighter: false, strokeEnabled: strokeEnabled)
        case .highlight:
            currentAnnotation = FreehandAnnotation(points: [point], color: safeColor, lineWidth: lineWidth, isHighlighter: true, strokeEnabled: strokeEnabled)
        case .arrow:
            currentAnnotation = ArrowAnnotation(startPoint: point, endPoint: point, color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .rectangle:
            currentAnnotation = RectAnnotation(rect: CGRect(origin: point, size: .zero), color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .ellipse:
            currentAnnotation = EllipseAnnotation(rect: CGRect(origin: point, size: .zero), color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .text:
            break
        case .mosaic:
            // 太さ1→2, 太さ5→8, 太さ10→14 くらいの緩やかな変化
            currentAnnotation = MosaicAnnotation(rect: CGRect(origin: point, size: .zero), pixelSize: max(Int(lineWidth * 1.2 + 1), 2), sourceImage: sourceImage)
        case .trim:
            break
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }

        let point = convert(event.locationInWindow, from: nil)

        // トリミングモードの場合
        if selectedTool == .trim, let start = trimDragStart {
            trimRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            needsDisplay = true
            return
        }

        // リサイズ中の場合
        if isResizing, let index = selectedAnnotationIndex, index < annotations.count {
            resizeAnnotation(at: index, to: point)
            needsDisplay = true
            return
        }

        // 移動モードで選択中のアノテーションがある場合
        if selectedTool == .move, let index = selectedAnnotationIndex, let lastPoint = lastDragPoint {
            let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
            annotations[index].move(by: delta)
            lastDragPoint = point
            didMoveAnnotation = true
            needsDisplay = true
            return
        }

        guard let start = dragStart else { return }

        let newRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )

        switch selectedTool {
        case .move:
            break
        case .pen, .highlight:
            if let freehand = currentAnnotation as? FreehandAnnotation {
                freehand.addPoint(point)
            }
        case .arrow:
            if let arrow = currentAnnotation as? ArrowAnnotation {
                arrow.endPoint = point
            }
        case .rectangle:
            if let rect = currentAnnotation as? RectAnnotation {
                rect.rect = newRect
            }
        case .ellipse:
            if let ellipse = currentAnnotation as? EllipseAnnotation {
                ellipse.rect = newRect
            }
        case .text:
            break
        case .mosaic:
            if let mosaic = currentAnnotation as? MosaicAnnotation {
                mosaic.rect = newRect
            }
        case .trim:
            break
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }

        // トリミングモードの場合
        if selectedTool == .trim {
            trimDragStart = nil
            // 小さすぎる矩形（10px未満）はクリア
            if let rect = trimRect, rect.width < 10 || rect.height < 10 {
                trimRect = nil
            }
            needsDisplay = true
            return
        }

        // リサイズ終了
        if isResizing {
            isResizing = false
            activeResizeHandle = .none
            delegate?.annotationMoved()
            needsDisplay = true
            return
        }

        // 移動モードでアノテーションを移動した場合（選択は保持）
        if selectedTool == .move && selectedAnnotationIndex != nil {
            // 実際に移動した場合のみ保存
            if didMoveAnnotation {
                delegate?.annotationMoved()
                didMoveAnnotation = false
            }
            lastDragPoint = nil
            needsDisplay = true
            return
        }

        if let annotation = currentAnnotation {
            // モザイクの場合はドラッグ終了フラグを設定
            if let mosaic = annotation as? MosaicAnnotation {
                mosaic.isDrawing = false
            }
            delegate?.annotationAdded(annotation)
        }
        currentAnnotation = nil
        dragStart = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete (51) または Backspace (117) キー
        if event.keyCode == 51 || event.keyCode == 117 {
            if selectedAnnotationIndex != nil {
                delegate?.deleteSelectedAnnotation()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    /// アノテーションのリサイズ処理
    private func resizeAnnotation(at index: Int, to point: CGPoint) {
        let annotation = annotations[index]

        if let arrow = annotation as? ArrowAnnotation {
            switch activeResizeHandle {
            case .startPoint:
                arrow.startPoint = point
            case .endPoint:
                arrow.endPoint = point
            default:
                break
            }
        } else if let rect = annotation as? RectAnnotation {
            rect.rect = resizedRect(original: rect.rect, handle: activeResizeHandle, to: point)
        } else if let ellipse = annotation as? EllipseAnnotation {
            ellipse.rect = resizedRect(original: ellipse.rect, handle: activeResizeHandle, to: point)
        } else if let mosaic = annotation as? MosaicAnnotation {
            mosaic.rect = resizedRect(original: mosaic.rect, handle: activeResizeHandle, to: point)
            mosaic.clearCache()
        }
    }

    /// リサイズ後の矩形を計算
    private func resizedRect(original: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var newRect = original

        switch handle {
        case .topLeft:
            newRect = CGRect(
                x: point.x,
                y: original.minY,
                width: original.maxX - point.x,
                height: point.y - original.minY
            )
        case .topRight:
            newRect = CGRect(
                x: original.minX,
                y: original.minY,
                width: point.x - original.minX,
                height: point.y - original.minY
            )
        case .bottomLeft:
            newRect = CGRect(
                x: point.x,
                y: point.y,
                width: original.maxX - point.x,
                height: original.maxY - point.y
            )
        case .bottomRight:
            newRect = CGRect(
                x: original.minX,
                y: point.y,
                width: point.x - original.minX,
                height: original.maxY - point.y
            )
        default:
            break
        }

        // 最小サイズを保証（幅・高さが負にならないように正規化）
        let minSize: CGFloat = 10
        if newRect.width < minSize || newRect.height < minSize {
            return CGRect(
                x: min(newRect.minX, newRect.maxX),
                y: min(newRect.minY, newRect.maxY),
                width: max(abs(newRect.width), minSize),
                height: max(abs(newRect.height), minSize)
            )
        }

        return newRect
    }

    // ぼかしを最背面（インデックス0）に移動
    private func moveMosaicToBack(at index: Int) {
        guard index < annotations.count, annotations[index] is MosaicAnnotation else { return }
        let mosaic = annotations.remove(at: index)
        annotations.insert(mosaic, at: 0)
        delegate?.annotationMoved()
    }

    // ぼかしを最前面（配列の最後）に移動
    private func moveMosaicToFront(at index: Int) {
        guard index < annotations.count, annotations[index] is MosaicAnnotation else { return }
        let mosaic = annotations.remove(at: index)
        annotations.append(mosaic)
        selectedAnnotationIndex = annotations.count - 1
        delegate?.annotationMoved()
    }

    // MARK: - トリミング右クリックメニュー

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectedTool == .trim, let trimRect = trimRect,
              trimRect.width >= 10, trimRect.height >= 10 else {
            return nil
        }

        let menu = NSMenu()
        let trimItem = NSMenuItem(title: "トリミング", action: #selector(executeTrim), keyEquivalent: "")
        trimItem.target = self
        menu.addItem(trimItem)

        let cancelItem = NSMenuItem(title: "キャンセル", action: #selector(cancelTrim), keyEquivalent: "")
        cancelItem.target = self
        menu.addItem(cancelItem)

        return menu
    }

    @objc private func executeTrim() {
        guard let trimRect = trimRect else { return }
        delegate?.trimRequested(rect: trimRect)
        self.trimRect = nil
        needsDisplay = true
    }

    @objc private func cancelTrim() {
        trimRect = nil
        needsDisplay = true
    }
}

