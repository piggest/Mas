import AppKit
import SwiftUI

// MARK: - SwiftUI 側のドラッグソース Representable

/// 編集中の画像を「外部アプリへドラッグ＆ドロップでコピー」できるようにする SwiftUI ラッパ。
/// 内部的には `DragSourceView` を生成し、ドラッグ開始時に PNG/GIF/動画ファイルを
/// 一時ディレクトリに書き出してドラッグアイテムとして提供する。
struct DraggableImageView: NSViewRepresentable {
    /// ドラッグ時に書き出す画像本体。
    let image: NSImage
    /// 画像が表示中かどうか（画像非表示モードでは外観に反映）。
    let showImage: Bool
    /// GIF/動画ファイルの場合のソース URL。指定があれば PNG 化せずそのままコピー対象にする。
    var gifURL: URL? = nil
    /// アノテーション付きの最新画像を取得するクロージャ（SwiftUI 更新タイミングに依存せず取得するため）。
    var imageProvider: (() -> NSImage?)? = nil
    /// ドラッグ成功時のコールバック（ウィンドウを閉じる等）。
    var onDragSuccess: (() -> Void)? = nil
    /// ドラッグ開始時のコールバック。
    var onDragStart: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.image = image
        view.showImage = showImage
        view.gifURL = gifURL
        view.imageProvider = imageProvider
        view.onDragSuccess = onDragSuccess
        view.onDragStart = onDragStart
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.image = image
        nsView.showImage = showImage
        nsView.gifURL = gifURL
        nsView.imageProvider = imageProvider
        nsView.onDragSuccess = onDragSuccess
        nsView.onDragStart = onDragStart
        nsView.needsDisplay = true
    }
}

// MARK: - 実体の NSView：ドラッグソース＆アイコン描画

/// 「外部へドラッグ可能なエクスポート用ビュー」の実装。
/// - 中央に共有アイコン（square.and.arrow.up）を描画
/// - mouseDragged 開始で一時ファイルを生成して `beginDraggingSession` を発火
/// - `NSDraggingSource` 側でドラッグ成功時のクリーンアップ・キャンセル時の再表示を扱う
class DragSourceView: NSView {
    var image: NSImage?
    var showImage: Bool = true
    var gifURL: URL?
    var imageProvider: (() -> NSImage?)?
    var onDragSuccess: (() -> Void)?
    var onDragStart: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ウィンドウ移動の対象から除外（このビュー上でのドラッグはウィンドウを動かさない）。
    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    /// 非アクティブウィンドウでも最初のクリックを受け付ける。
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

        // 中央の共有アイコン
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
        onDragStart?()
    }

    /// ドラッグ開始時に一時ファイルを生成して `NSDraggingSession` を起動する。
    override func mouseDragged(with event: NSEvent) {
        // imageProvider で最新のアノテーション付き画像を取得（SwiftUI 更新タイミングに依存しない）
        let image = imageProvider?() ?? self.image
        guard let image else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL: URL

        if let gifSource = gifURL, FileManager.default.fileExists(atPath: gifSource.path) {
            // GIF/動画ファイルはそのままコピー（再エンコードしない）
            let ext = gifSource.pathExtension.lowercased()
            let fileName = "Mas_Recording_\(Int(Date().timeIntervalSince1970)).\(ext)"
            fileURL = tempDir.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: gifSource, to: fileURL)
        } else {
            // 画像は PNG として書き出す
            let fileName = "Mas_Screenshot_\(Int(Date().timeIntervalSince1970)).png"
            fileURL = tempDir.appendingPathComponent(fileName)
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
            }
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

        // ドラッグ中に追従するサムネイル（半透明の小さい画像）
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

// MARK: - NSDraggingSource: ドラッグセッションのライフサイクル

extension DragSourceView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // ドラッグ開始時にウィンドウを非表示にして、視覚的な邪魔を避ける
        window?.orderOut(nil)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // ドラッグ成功時（コピー操作が行われた場合）
        if !operation.isEmpty {
            let closeOnDragSuccess = UserDefaults.standard.object(forKey: "closeOnDragSuccess") as? Bool ?? true
            if closeOnDragSuccess {
                // ドラッグ前のウィンドウ位置を「次回キャプチャ位置」として保存
                if let frame = window?.frame {
                    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                    let rectDict: [String: CGFloat] = [
                        "x": frame.origin.x,
                        "y": screenHeight - frame.origin.y - frame.height,
                        "width": frame.width, "height": frame.height
                    ]
                    UserDefaults.standard.set(rectDict, forKey: "lastCaptureRect")
                }
                // アノテーション適用とクリーンアップ
                onDragSuccess?()
                window?.close()
                NotificationCenter.default.post(name: .editorWindowClosed, object: nil)
                return
            }
        }
        // キャンセル or 設定で「閉じない」場合はウィンドウを復活させる
        window?.makeKeyAndOrderFront(nil)
    }
}
