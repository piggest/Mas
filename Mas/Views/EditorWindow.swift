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
    case move = "移動"
    case pen = "ペン"
    case highlight = "マーカー"
    case arrow = "矢印"
    case rectangle = "四角"
    case ellipse = "丸"
    case text = "文字"
    case mosaic = "ぼかし"

    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
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
            ZStack(alignment: .bottom) {
                // 画像コンテンツ
                ZStack(alignment: .topLeading) {
                    imageContent
                    closeButton
                    editModeToggle(geometry: geometry)
                    topRightButtons(geometry: geometry)
                    dragArea(geometry: geometry)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 下からスライドするツールバー（オーバーレイ）
                if editMode {
                    InlineToolboxView(state: toolboxState) {
                        _ = toolboxState.annotations.popLast()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .animation(.easeInOut(duration: 0.25), value: editMode)
    }

    @ViewBuilder
    private var imageContent: some View {
        if showImage {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    screenshotImage
                    // 編集モードまたはアノテーションがある場合は表示
                    if editMode || !toolboxState.annotations.isEmpty {
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
            strokeEnabled: toolboxState.strokeEnabled,
            sourceImage: screenshot.originalImage,
            onTextTap: { position in
                textPosition = position
                showTextInput = true
            },
            onAnnotationChanged: {
                applyAnnotationsToImage()
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
                // 編集モード終了時もアノテーションは保持（自動保存のみ）
                if !editMode && !toolboxState.annotations.isEmpty {
                    applyAnnotationsToImage()
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

    // アノテーションを画像に反映して自動保存（アノテーションは保持）
    private func applyAnnotationsToImage() {
        guard !toolboxState.annotations.isEmpty else { return }

        // 現在のアノテーション情報をキャプチャ
        let annotations = toolboxState.annotations
        let originalImage = screenshot.originalImage
        let captureRegion = screenshot.captureRegion
        let savedURL = screenshot.savedURL

        // バックグラウンドで処理（UIをブロックしない）
        DispatchQueue.global(qos: .userInitiated).async {
            let renderedImage = Self.renderImageInBackground(
                originalImage: originalImage,
                annotations: annotations,
                captureRegion: captureRegion
            )

            guard let image = renderedImage else { return }

            let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
            if autoSaveEnabled {
                Self.saveImageToFile(image, url: savedURL)
            }

            let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
            if autoCopyToClipboard {
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                }
            }
        }
    }

    // バックグラウンドで画像をレンダリング
    private static func renderImageInBackground(originalImage: NSImage, annotations: [any Annotation], captureRegion: CGRect?) -> NSImage? {
        let imageSize = originalImage.size
        let canvasSize = captureRegion?.size ?? imageSize
        let scale = imageSize.width / canvasSize.width

        // CGContextを使ってバックグラウンドで描画
        guard let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 元画像を描画
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))

        // NSGraphicsContextを作成してアノテーションを描画
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

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

        // モザイク適用済み画像を再描画
        if let mosaicCgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(mosaicCgImage, in: CGRect(origin: .zero, size: imageSize))
        }

        // その他のアノテーションを描画
        for annotation in annotations {
            if !(annotation is MosaicAnnotation) {
                Self.drawScaledAnnotationStatic(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let resultCgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: resultCgImage, size: imageSize)
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
                color: arrow.color,
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
                color: rect.color,
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
                color: ellipse.color,
                lineWidth: ellipse.lineWidth * scale,
                strokeEnabled: ellipse.strokeEnabled
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

    private func closeWindow() {
        if editMode && !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }
        toolboxState.annotations.removeAll()
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
    let strokeEnabled: Bool
    let sourceImage: NSImage
    let onTextTap: (CGPoint) -> Void
    let onAnnotationChanged: () -> Void

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
        nsView.strokeEnabled = strokeEnabled
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
            parent.onAnnotationChanged()
        }

        func currentAnnotationUpdated(_ annotation: (any Annotation)?) {
            parent.currentAnnotation = annotation
        }

        func textTapped(at position: CGPoint) {
            parent.onTextTap(position)
        }

        func annotationMoved() {
            parent.onAnnotationChanged()
        }
    }
}

protocol AnnotationCanvasDelegate: AnyObject {
    func annotationAdded(_ annotation: any Annotation)
    func currentAnnotationUpdated(_ annotation: (any Annotation)?)
    func textTapped(at position: CGPoint)
    func annotationMoved()
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
    private var dragStart: CGPoint?
    private var selectedAnnotationIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMoveAnnotation: Bool = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for (index, annotation) in annotations.enumerated() {
            annotation.draw(in: bounds)
            // 選択されたアノテーションにハイライト
            if selectedTool == .move && index == selectedAnnotationIndex {
                drawSelectionHighlight(for: annotation)
            }
        }

        currentAnnotation?.draw(in: bounds)
    }

    private func drawSelectionHighlight(for annotation: any Annotation) {
        let highlightPath = NSBezierPath()
        highlightPath.lineWidth = 2

        if let arrow = annotation as? ArrowAnnotation {
            let minX = min(arrow.startPoint.x, arrow.endPoint.x) - 10
            let minY = min(arrow.startPoint.y, arrow.endPoint.y) - 10
            let maxX = max(arrow.startPoint.x, arrow.endPoint.x) + 10
            let maxY = max(arrow.startPoint.y, arrow.endPoint.y) + 10
            highlightPath.appendRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        } else if let rect = annotation as? RectAnnotation {
            highlightPath.appendRect(rect.rect.insetBy(dx: -5, dy: -5))
        } else if let ellipse = annotation as? EllipseAnnotation {
            highlightPath.appendRect(ellipse.rect.insetBy(dx: -5, dy: -5))
        } else if let text = annotation as? TextAnnotation {
            let size = text.textSize()
            highlightPath.appendRect(CGRect(origin: CGPoint(x: text.position.x - 5, y: text.position.y - size.height - 5), size: CGSize(width: size.width + 10, height: size.height + 10)))
        } else if let mosaic = annotation as? MosaicAnnotation {
            highlightPath.appendRect(mosaic.rect.insetBy(dx: -5, dy: -5))
        } else if let freehand = annotation as? FreehandAnnotation {
            if let minX = freehand.points.map({ $0.x }).min(),
               let minY = freehand.points.map({ $0.y }).min(),
               let maxX = freehand.points.map({ $0.x }).max(),
               let maxY = freehand.points.map({ $0.y }).max() {
                highlightPath.appendRect(CGRect(x: minX - 5, y: minY - 5, width: maxX - minX + 10, height: maxY - minY + 10))
            }
        }

        let dashPattern: [CGFloat] = [4, 4]
        highlightPath.setLineDash(dashPattern, count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        highlightPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        lastDragPoint = point

        // 移動モードの場合
        if selectedTool == .move {
            // クリックした位置にあるアノテーションを探す
            let clickedIndices = annotations.enumerated().filter { $0.element.contains(point: point) }.map { $0.offset }

            if clickedIndices.isEmpty {
                // 何もない場所をクリック
                selectedAnnotationIndex = nil
            } else if let currentIndex = selectedAnnotationIndex, clickedIndices.contains(currentIndex) {
                // 選択中のオブジェクトがクリックされた場合
                // 現在選択中のオブジェクトを配列の先頭（一番後ろ）に移動
                let movedAnnotation = annotations.remove(at: currentIndex)
                annotations.insert(movedAnnotation, at: 0)

                // 同じ位置にある他のオブジェクトを選択（一番上のもの）
                let newClickedIndices = annotations.enumerated().filter { $0.element.contains(point: point) }.map { $0.offset }
                if let lastIndex = newClickedIndices.last, lastIndex != 0 {
                    selectedAnnotationIndex = lastIndex
                } else if newClickedIndices.count > 1 {
                    // 先頭に移動したオブジェクト以外で一番上のものを選択
                    selectedAnnotationIndex = newClickedIndices.filter { $0 != 0 }.last
                } else {
                    // 他にオブジェクトがない場合は先頭のものを選択
                    selectedAnnotationIndex = 0
                }
                // Zオーダー変更だけでは保存しない
            } else {
                // 新しいオブジェクトを選択（一番上のもの）
                selectedAnnotationIndex = clickedIndices.last
            }
            needsDisplay = true
            return
        }

        if selectedTool == .text {
            delegate?.textTapped(at: point)
            return
        }

        switch selectedTool {
        case .move:
            break
        case .pen:
            currentAnnotation = FreehandAnnotation(points: [point], color: selectedColor, lineWidth: lineWidth, isHighlighter: false, strokeEnabled: strokeEnabled)
        case .highlight:
            currentAnnotation = FreehandAnnotation(points: [point], color: selectedColor, lineWidth: lineWidth, isHighlighter: true, strokeEnabled: strokeEnabled)
        case .arrow:
            currentAnnotation = ArrowAnnotation(startPoint: point, endPoint: point, color: selectedColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .rectangle:
            currentAnnotation = RectAnnotation(rect: CGRect(origin: point, size: .zero), color: selectedColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .ellipse:
            currentAnnotation = EllipseAnnotation(rect: CGRect(origin: point, size: .zero), color: selectedColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .text:
            break
        case .mosaic:
            currentAnnotation = MosaicAnnotation(rect: CGRect(origin: point, size: .zero), pixelSize: Int(lineWidth * 3), sourceImage: sourceImage)
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

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
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
}

// インラインツールバー（ウィンドウ下部に表示）
struct InlineToolboxView: View {
    @ObservedObject var state: ToolboxState
    let onUndo: () -> Void

    private let colors: [Color] = [.red, .blue, .green, .yellow, .black, .white]

    var body: some View {
        HStack(spacing: 12) {
            // ツール選択
            HStack(spacing: 4) {
                ForEach(EditTool.allCases, id: \.self) { tool in
                    Button(action: { state.selectedTool = tool }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(state.selectedTool == tool ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(state.selectedTool == tool ? Color.blue : Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(tool.rawValue)
                }
            }

            Divider()
                .frame(height: 24)

            // 色選択
            HStack(spacing: 4) {
                ForEach(colors, id: \.self) { color in
                    Button(action: { state.selectedColor = color }) {
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(state.selectedColor == color ? Color.blue : Color.gray.opacity(0.3), lineWidth: state.selectedColor == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .frame(height: 24)

            // サイズスライダー
            HStack(spacing: 4) {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Slider(value: $state.lineWidth, in: 1...10, step: 1)
                    .frame(width: 60)
                Image(systemName: "line.diagonal")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 24)

            // 縁取りトグル
            Button(action: { state.strokeEnabled.toggle() }) {
                Image(systemName: state.strokeEnabled ? "square.dashed" : "square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.strokeEnabled ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(state.strokeEnabled ? Color.blue : Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("縁取り")

            // 取消ボタン
            if !state.annotations.isEmpty {
                Divider()
                    .frame(height: 24)

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("取消")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
    }
}
