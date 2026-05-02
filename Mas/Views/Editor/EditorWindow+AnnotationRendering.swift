import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - アノテーション焼き付け・画像レンダリング
//
// 編集中のアノテーションを画像（または GIF/動画サムネイル）に焼き付ける処理一式。
// EditorWindow から SwiftUI/AppKit 状態を参照する必要があるため extension として分離。
//
// - expandWindowForAnnotations    : アノテーションのはみ出しに合わせてウィンドウを拡張
// - applyAnnotationsToImage       : 編集中の画像にアノテーションを焼き付け autoSave
// - applyAnnotationsToImageSafe   : main 外スレッドで使う safe 版
// - applyAnnotationsToGif         : GIF の各フレームにアノテーションを焼き付けて再エンコード
// - reencodeGif (static)          : NSImage 配列 + delays から GIF を ImageIO で書き出す
// - renderImageInBackground (static) : 同期レンダリング処理（バックグラウンド呼び出し用）
// - saveImageToFile (static)      : NSImage を URL に PNG/JPG で書き出し
// - renderImageWithAnnotations    : 画面上の最終画像を NSImage として返す
// - applyAnnotations              : 編集モード終了時にアノテーションを焼き付け、状態を空に
// - drawScaledAnnotationStatic    : 1 アノテーションを縮尺・座標変換しつつ NSGraphicsContext に描画

extension EditorWindow {

    // アノテーションがはみ出した場合にウィンドウを自動拡張
    func expandWindowForAnnotations() {
        guard let window = parentWindow else { return }
        let imageWidth = screenshot.captureRegion?.width ?? screenshot.originalImage.size.width
        let imageHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
        let imageRect = CGRect(origin: .zero, size: CGSize(width: imageWidth, height: imageHeight))

        var expandedRect = imageRect
        for annotation in toolboxState.annotations {
            expandedRect = expandedRect.union(annotation.boundingRect())
        }

        // 各方向のはみ出し量（NSView非flipped座標系: y=0が下端、上方向に増加）
        let overflowUp = max(0, expandedRect.maxY - imageHeight)    // 視覚的な上はみ出し
        let overflowDown = max(0, -expandedRect.origin.y)           // 視覚的な下はみ出し
        let overflowLeft = max(0, -expandedRect.origin.x)
        let overflowRight = max(0, expandedRect.maxX - imageWidth)

        let maxOverflowX = max(overflowLeft, overflowRight)
        let maxOverflowY = max(overflowUp, overflowDown)

        let requiredWidth = imageWidth + maxOverflowX
        let requiredHeight = imageHeight + maxOverflowY

        let currentFrame = window.frame
        guard requiredWidth > currentFrame.width || requiredHeight > currentFrame.height else { return }

        let newWidth = max(currentFrame.width, requiredWidth)
        let newHeight = max(currentFrame.height, requiredHeight)
        let deltaH = newHeight - currentFrame.height

        // 上方向に拡張 + contentYOffsetで画像位置を補正
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(newFrame, display: true, animate: false)
        contentYOffset += deltaH
    }

    // アノテーションを画像に反映して自動保存（アノテーションは保持）
    func applyAnnotationsToImage() {
        guard !toolboxState.annotations.isEmpty else { return }
        // GIF/動画モードでは中間保存しない
        if screenshot.isGif || screenshot.isVideo { return }

        // アノテーションデータを保存
        onAnnotationsSaved?(toolboxState.annotations)

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
    func applyAnnotationsToImageSafe(annotations: [any Annotation], originalImage: NSImage, captureRegion: CGRect?, savedURL: URL?) {
        guard !annotations.isEmpty else { return }

        // アノテーションデータを保存（クリア前に）
        onAnnotationsSaved?(annotations)

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

    // GIF全フレームにアノテーションを焼き込んで再保存
    func applyAnnotationsToGif() {
        guard let player = gifPlayerState, !toolboxState.annotations.isEmpty else { return }

        let annotations = toolboxState.annotations
        let captureRegion = screenshot.captureRegion

        // 各フレームにアノテーションを描画
        var annotatedFrames: [NSImage] = []
        for frame in player.frames {
            if let rendered = Self.renderImageInBackground(
                originalImage: frame,
                annotations: annotations,
                captureRegion: captureRegion
            ) {
                annotatedFrames.append(rendered)
            } else {
                annotatedFrames.append(frame)
            }
        }

        // フレームを更新
        player.replaceFrames(annotatedFrames)

        // アノテーションをクリア
        toolboxState.annotations.removeAll()
        imageForDrag = nil

        // GIFファイルを再エンコードして保存
        if let savedURL = screenshot.savedURL {
            DispatchQueue.global(qos: .userInitiated).async {
                Self.reencodeGif(frames: annotatedFrames, delays: player.frameDelays, to: savedURL)
            }
        }
    }

    // GIFフレームをファイルに再エンコード
    static func reencodeGif(frames: [NSImage], delays: [Double], to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            frames.count,
            nil
        ) else { return }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        for (i, frame) in frames.enumerated() {
            guard let cgImage = frame.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let delay = i < delays.count ? delays[i] : 0.1
            let frameProperties: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay
                ]
            ]
            CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
        }

        CGImageDestinationFinalize(destination)
    }

    // バックグラウンドで画像をレンダリング
    static func renderImageInBackground(originalImage: NSImage, annotations: [any Annotation], captureRegion: CGRect?) -> NSImage? {
        let imageSize = originalImage.size
        let canvasSize = captureRegion?.size ?? imageSize
        let scale = imageSize.width / canvasSize.width

        // アノテーションのはみ出しを含む拡張キャンバスを計算
        var expandedCanvas = CGRect(origin: .zero, size: canvasSize)
        for annotation in annotations {
            expandedCanvas = expandedCanvas.union(annotation.boundingRect())
        }
        let offset = CGPoint(x: -expandedCanvas.origin.x * scale, y: -expandedCanvas.origin.y * scale)
        let expandedImageSize = NSSize(
            width: expandedCanvas.width * scale,
            height: expandedCanvas.height * scale
        )

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

        // NSImageのlockFocusを使用して描画（フリップキャンバスに合わせる）
        let resultImage = NSImage(size: expandedImageSize)
        resultImage.lockFocus()

        // はみ出し領域を白で塗りつぶし
        if expandedImageSize != imageSize {
            NSColor.white.setFill()
            NSRect(origin: .zero, size: expandedImageSize).fill()
        }

        // モザイク適用済み画像をオフセット付きで描画
        baseImage.draw(in: NSRect(origin: CGPoint(x: offset.x, y: offset.y), size: imageSize))

        // その他のアノテーションを描画
        for annotation in annotations {
            if !(annotation is MosaicAnnotation) {
                Self.drawScaledAnnotationStatic(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height, offset: offset)
            }
        }

        resultImage.unlockFocus()
        return resultImage
    }

    // ファイルに保存（バックグラウンド用）
    static func saveImageToFile(_ image: NSImage, url: URL?) {
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
    func renderImageWithAnnotations() -> NSImage {
        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize
        let scale = imageSize.width / canvasSize.width

        // アノテーションのはみ出しを含む拡張キャンバスを計算
        var expandedCanvas = CGRect(origin: .zero, size: canvasSize)
        for annotation in toolboxState.annotations {
            expandedCanvas = expandedCanvas.union(annotation.boundingRect())
        }
        let offset = CGPoint(x: -expandedCanvas.origin.x * scale, y: -expandedCanvas.origin.y * scale)
        let expandedImageSize = NSSize(
            width: expandedCanvas.width * scale,
            height: expandedCanvas.height * scale
        )

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

        let newImage = NSImage(size: expandedImageSize)
        newImage.lockFocus()

        // はみ出し領域を白で塗りつぶし
        if expandedImageSize != imageSize {
            NSColor.white.setFill()
            NSRect(origin: .zero, size: expandedImageSize).fill()
        }

        baseImage.draw(in: NSRect(origin: CGPoint(x: offset.x, y: offset.y), size: imageSize))

        for annotation in toolboxState.annotations {
            if !(annotation is MosaicAnnotation) {
                Self.drawScaledAnnotationStatic(annotation, scale: scale, imageHeight: imageSize.height, canvasHeight: canvasSize.height, offset: offset)
            }
        }

        newImage.unlockFocus()
        return newImage
    }

    func applyAnnotations() {
        guard !toolboxState.annotations.isEmpty else { return }

        // アノテーションデータを保存（クリア前に）
        onAnnotationsSaved?(toolboxState.annotations)

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

    static func drawScaledAnnotationStatic(_ annotation: any Annotation, scale: CGFloat, imageHeight: CGFloat, canvasHeight: CGFloat, offset: CGPoint = .zero) {
        // 単純にスケーリング + オフセット（NSViewとNSImageは同じ左下原点座標系）
        let ox = offset.x
        let oy = offset.y
        if let line = annotation as? LineAnnotation {
            let startPoint = CGPoint(
                x: line.startPoint.x * scale + ox,
                y: line.startPoint.y * scale + oy
            )
            let endPoint = CGPoint(
                x: line.endPoint.x * scale + ox,
                y: line.endPoint.y * scale + oy
            )
            let scaledLine = LineAnnotation(
                startPoint: startPoint,
                endPoint: endPoint,
                color: line.color.copy() as! NSColor,
                lineWidth: line.lineWidth * scale,
                strokeEnabled: line.strokeEnabled
            )
            scaledLine.draw(in: .zero)
        } else if let arrow = annotation as? ArrowAnnotation {
            let startPoint = CGPoint(
                x: arrow.startPoint.x * scale + ox,
                y: arrow.startPoint.y * scale + oy
            )
            let endPoint = CGPoint(
                x: arrow.endPoint.x * scale + ox,
                y: arrow.endPoint.y * scale + oy
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
                x: rect.rect.origin.x * scale + ox,
                y: rect.rect.origin.y * scale + oy,
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
                x: ellipse.rect.origin.x * scale + ox,
                y: ellipse.rect.origin.y * scale + oy,
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
                x: text.position.x * scale + ox,
                y: text.position.y * scale + oy
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
                x: highlight.rect.origin.x * scale + ox,
                y: highlight.rect.origin.y * scale + oy,
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
                x: mosaic.rect.origin.x * scale + ox,
                y: mosaic.rect.origin.y * scale + oy,
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
                CGPoint(x: point.x * scale + ox, y: point.y * scale + oy)
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
}
