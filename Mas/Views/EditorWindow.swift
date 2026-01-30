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

    // ウィンドウ移動を完全にブロック
    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景
        let bgColor = showImage ? NSColor.black.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(0.8)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        path.fill()

        // アイコン
        let iconColor = showImage ? NSColor.white : NSColor.gray
        if let symbolImage = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            let configuredImage = symbolImage.withSymbolConfiguration(config)
            configuredImage?.lockFocus()
            iconColor.set()
            let imageRect = NSRect(x: 0, y: 0, width: configuredImage?.size.width ?? 0, height: configuredImage?.size.height ?? 0)
            imageRect.fill(using: .sourceAtop)
            configuredImage?.unlockFocus()

            let iconSize: CGFloat = 18
            let iconRect = NSRect(
                x: (bounds.width - iconSize) / 2,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            configuredImage?.draw(in: iconRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // ウィンドウ移動をブロック - 何もしない
    }

    override func mouseDragged(with event: NSEvent) {
        guard let image = image else { return }

        // 一時ファイルに保存
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Mas_Screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)

        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

        // ドラッグ時のプレビュー画像
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

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @State private var copiedToClipboard = false
    @State private var showImage = true
    @State private var passThroughEnabled = false

    let onRecapture: ((CGRect) -> Void)?
    let onPassThroughChanged: ((Bool) -> Void)?

    init(screenshot: Screenshot, onRecapture: ((CGRect) -> Void)? = nil, onPassThroughChanged: ((Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.onRecapture = onRecapture
        self.onPassThroughChanged = onPassThroughChanged
    }

    private func getCurrentWindowRect() -> CGRect {
        // すべてのウィンドウからMasのウィンドウを探す
        for window in NSApp.windows {
            // floating levelのウィンドウを探す
            if window.level == .floating && window.isVisible {
                let frame = window.frame
                let screenHeight = NSScreen.main?.frame.height ?? 0
                // 左下原点から左上原点に変換
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
                // 画像をスクロール可能に表示
                if showImage {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        if let region = screenshot.captureRegion {
                            Image(nsImage: screenshot.originalImage)
                                .resizable()
                                .frame(width: region.width, height: region.height)
                        } else {
                            Image(nsImage: screenshot.originalImage)
                        }
                    }
                }

                // 閉じるボタン（左上）
                Button(action: {
                    closeWindow()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(showImage ? .white : .gray)
                        .padding(6)
                        .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: 20, y: 20)

                // ボタン群（常に右上に固定）
                if screenshot.captureRegion != nil {
                    HStack(spacing: 4) {
                        // パススルートグル（画像非表示時のみ）
                        if !showImage {
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

                        // 再キャプチャボタン
                        Button(action: {
                            let rect = getCurrentWindowRect()
                            onRecapture?(rect)
                            showImage = true
                            // 再キャプチャ時はパススルーをOFFに
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
                    .position(x: geometry.size.width - (showImage ? 20 : 36), y: 20)
                }

                // ドラッグ領域（右下）
                DraggableImageView(image: screenshot.originalImage, showImage: showImage)
                    .frame(width: 32, height: 32)
                    .position(x: geometry.size.width - 24, y: geometry.size.height - 24)
            }
        }
        .frame(minWidth: 50, minHeight: 50)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showImage = false
        }
        .border(Color.gray.opacity(0.5), width: 1)
        .contextMenu {
            Button("閉じる") {
                closeWindow()
            }
            Divider()
            Button("クリップボードにコピー") {
                copyToClipboard()
            }
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
        // floatingレベルのウィンドウ（エディタウィンドウ）を閉じる
        for window in NSApp.windows {
            if window.level == .floating && window.isVisible {
                window.close()
                return
            }
        }
    }

    private func createDragItem() -> NSItemProvider {
        // 一時ファイルに画像を保存
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Mas_Screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)

        if let tiffData = screenshot.originalImage.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        }

        let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        return provider
    }
}
