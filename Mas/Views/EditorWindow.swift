import SwiftUI

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
}

// 編集ツールの種類
enum EditTool: String, CaseIterable {
    case pen = "ペン"
    case highlight = "マーカー"
    case arrow = "矢印"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "文字"
    case mosaic = "ぼかし"

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlight: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3"
        }
    }
}

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @ObservedObject private var toolboxState = ToolboxState.shared
    @State private var copiedToClipboard = false
    @State private var showImage = true
    @State private var passThroughEnabled = false
    @State private var editMode = false
    @State private var currentAnnotation: (any Annotation)?
    @State private var textInput: String = ""
    @State private var showTextInput = false
    @State private var textPosition: CGPoint = .zero

    let onRecapture: ((CGRect) -> Void)?
    let onPassThroughChanged: ((Bool) -> Void)?

    init(screenshot: Screenshot, onRecapture: ((CGRect) -> Void)? = nil, onPassThroughChanged: ((Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.onRecapture = onRecapture
        self.onPassThroughChanged = onPassThroughChanged
    }

    private func getCurrentWindowRect() -> CGRect {
        for window in NSApp.windows {
            if window.level == .floating && window.isVisible {
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
        }
        return screenshot.captureRegion ?? .zero
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                imageContent
                closeButton
                editModeToggle(geometry: geometry)
                topRightButtons(geometry: geometry)
                dragArea(geometry: geometry)
            }
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
        .sheet(isPresented: $showTextInput) {
            TextInputSheet(text: $textInput, onSubmit: {
                if !textInput.isEmpty {
                    let textAnnotation = TextAnnotation(
                        position: textPosition,
                        text: textInput,
                        font: .systemFont(ofSize: toolboxState.lineWidth * 5, weight: .medium),
                        color: NSColor(toolboxState.selectedColor)
                    )
                    toolboxState.annotations.append(textAnnotation)
                    textInput = ""
                }
                showTextInput = false
            })
        }
        .onChange(of: editMode) { newValue in
            if newValue {
                showToolboxWindow()
            } else {
                ToolboxWindowController.shared.hide()
            }
        }
    }

    private func showToolboxWindow() {
        // エディタウィンドウの位置を取得
        for window in NSApp.windows {
            if window.level == .floating && window.isVisible {
                ToolboxWindowController.shared.show(near: window.frame) { [self] in
                    _ = toolboxState.annotations.popLast()
                }
                break
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if showImage {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    screenshotImage
                    if editMode {
                        annotationCanvas
                    }
                }
            }
        }
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
        AnnotationCanvasView(
            annotations: $toolboxState.annotations,
            currentAnnotation: $currentAnnotation,
            selectedTool: toolboxState.selectedTool,
            selectedColor: NSColor(toolboxState.selectedColor),
            lineWidth: toolboxState.lineWidth,
            sourceImage: screenshot.originalImage,
            onTextTap: { position in
                textPosition = position
                showTextInput = true
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
        .buttonStyle(.plain)
        .position(x: 20, y: 20)
    }

    @ViewBuilder
    private func editModeToggle(geometry: GeometryProxy) -> some View {
        if showImage {
            Button(action: {
                editMode.toggle()
                if !editMode && !toolboxState.annotations.isEmpty {
                    applyAnnotations()
                }
            }) {
                Image(systemName: editMode ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(editMode ? .blue : .white)
                    .padding(8)
                    .background(editMode ? Color.white.opacity(0.9) : Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 24, y: geometry.size.height - 24)
        }
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
        .buttonStyle(.plain)
    }

    private var recaptureButton: some View {
        Button(action: {
            let rect = getCurrentWindowRect()
            onRecapture?(rect)
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
        .buttonStyle(.plain)
    }

    private func dragArea(geometry: GeometryProxy) -> some View {
        DraggableImageView(image: screenshot.originalImage, showImage: showImage)
            .frame(width: 32, height: 32)
            .position(x: geometry.size.width - 24, y: geometry.size.height - 24)
    }

    private func applyAnnotations() {
        guard !toolboxState.annotations.isEmpty else { return }

        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize

        // スケールファクターを計算（Retina対応）
        let scale = imageSize.width / canvasSize.width

        // まずモザイク効果を適用（画像自体を変更）
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

        // モザイク適用済みの画像を描画
        baseImage.draw(in: NSRect(origin: .zero, size: imageSize))

        // モザイク以外の注釈を描画
        for annotation in toolboxState.annotations {
            if !(annotation is MosaicAnnotation) {
                drawScaledAnnotation(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height)
            }
        }

        newImage.unlockFocus()

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

    private func drawScaledAnnotation(_ annotation: any Annotation, scale: CGFloat, imageHeight: CGFloat, canvasHeight: CGFloat) {
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
                color: arrow.color,
                lineWidth: arrow.lineWidth * scale
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
                color: rect.color,
                lineWidth: rect.lineWidth * scale
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
                color: ellipse.color,
                lineWidth: ellipse.lineWidth * scale
            )
            scaledAnnotation.draw(in: .zero)
        } else if let text = annotation as? TextAnnotation {
            let scaledFont = NSFont.systemFont(ofSize: text.font.pointSize * scale, weight: .medium)
            // 単純にスケーリング（調整はTextAnnotation.draw()内で行う）
            let scaledPosition = CGPoint(
                x: text.position.x * scale,
                y: text.position.y * scale
            )
            let scaledAnnotation = TextAnnotation(
                position: scaledPosition,
                text: text.text,
                font: scaledFont,
                color: text.color
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
                color: highlight.color
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
                color: freehand.color,
                lineWidth: freehand.lineWidth * scale,
                isHighlighter: freehand.isHighlighter
            )
            scaledAnnotation.draw(in: .zero)
        }
    }

    private func saveEditedImage(_ image: NSImage) {
        let saveFolder = UserDefaults.standard.string(forKey: "autoSaveFolder") ?? "~/Pictures/Mas"
        let expandedPath = NSString(string: saveFolder).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath)

        let formatString = UserDefaults.standard.string(forKey: "defaultFormat") ?? "PNG"
        let fileExtension = formatString.lowercased()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "Mas_\(dateFormatter.string(from: Date())).\(fileExtension)"
        let fileURL = folderURL.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return }

        let imageData: Data?
        if formatString == "JPEG" {
            let quality = UserDefaults.standard.double(forKey: "jpegQuality")
            imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality > 0 ? quality : 0.9])
        } else {
            imageData = bitmapRep.representation(using: .png, properties: [:])
        }

        try? imageData?.write(to: fileURL)
    }

    private func copyToClipboard() {
        if viewModel.copyToClipboard() {
            copiedToClipboard = true
        }
    }

    private func updatePassThrough() {
        onPassThroughChanged?(passThroughEnabled)
    }

    private func closeWindow() {
        if editMode && !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }
        ToolboxWindowController.shared.close()
        toolboxState.reset()
        for window in NSApp.windows {
            if window.level == .floating && window.isVisible {
                window.close()
                return
            }
        }
    }
}

// テキスト入力シート
struct TextInputSheet: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("テキストを入力")
                .font(.headline)
            TextField("テキスト", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            HStack {
                Button("キャンセル") {
                    text = ""
                    onSubmit()
                }
                Button("追加") {
                    onSubmit()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 280, height: 120)
    }
}

// 注釈描画キャンバス
struct AnnotationCanvasView: NSViewRepresentable {
    @Binding var annotations: [any Annotation]
    @Binding var currentAnnotation: (any Annotation)?
    let selectedTool: EditTool
    let selectedColor: NSColor
    let lineWidth: CGFloat
    let sourceImage: NSImage
    let onTextTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> AnnotationCanvas {
        let canvas = AnnotationCanvas()
        canvas.delegate = context.coordinator
        canvas.sourceImage = sourceImage
        return canvas
    }

    func updateNSView(_ nsView: AnnotationCanvas, context: Context) {
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.selectedTool = selectedTool
        nsView.selectedColor = selectedColor
        nsView.lineWidth = lineWidth
        nsView.sourceImage = sourceImage
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AnnotationCanvasDelegate {
        var parent: AnnotationCanvasView

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func annotationAdded(_ annotation: any Annotation) {
            parent.annotations.append(annotation)
            parent.currentAnnotation = nil
        }

        func currentAnnotationUpdated(_ annotation: (any Annotation)?) {
            parent.currentAnnotation = annotation
        }

        func textTapped(at position: CGPoint) {
            parent.onTextTap(position)
        }
    }
}

protocol AnnotationCanvasDelegate: AnyObject {
    func annotationAdded(_ annotation: any Annotation)
    func currentAnnotationUpdated(_ annotation: (any Annotation)?)
    func textTapped(at position: CGPoint)
}

class AnnotationCanvas: NSView {
    weak var delegate: AnnotationCanvasDelegate?
    var annotations: [any Annotation] = []
    var currentAnnotation: (any Annotation)?
    var selectedTool: EditTool = .arrow
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 3
    var sourceImage: NSImage?
    private var dragStart: CGPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for annotation in annotations {
            annotation.draw(in: bounds)
        }

        currentAnnotation?.draw(in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        if selectedTool == .text {
            delegate?.textTapped(at: point)
            return
        }

        switch selectedTool {
        case .pen:
            currentAnnotation = FreehandAnnotation(points: [point], color: selectedColor, lineWidth: lineWidth, isHighlighter: false)
        case .highlight:
            currentAnnotation = FreehandAnnotation(points: [point], color: selectedColor, lineWidth: lineWidth, isHighlighter: true)
        case .arrow:
            currentAnnotation = ArrowAnnotation(startPoint: point, endPoint: point, color: selectedColor, lineWidth: lineWidth)
        case .rectangle:
            currentAnnotation = RectAnnotation(rect: CGRect(origin: point, size: .zero), color: selectedColor, lineWidth: lineWidth)
        case .ellipse:
            currentAnnotation = EllipseAnnotation(rect: CGRect(origin: point, size: .zero), color: selectedColor, lineWidth: lineWidth)
        case .text:
            break
        case .mosaic:
            currentAnnotation = MosaicAnnotation(rect: CGRect(origin: point, size: .zero), pixelSize: Int(lineWidth * 3), sourceImage: sourceImage)
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)

        let newRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )

        switch selectedTool {
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
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
}
