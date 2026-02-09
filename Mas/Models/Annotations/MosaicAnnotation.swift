import AppKit
import Foundation
import CoreImage

class MosaicAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var pixelSize: Int
    var sourceImage: NSImage?
    var isDrawing: Bool = true  // ドラッグ中かどうか
    var useRealTimeCapture: Bool = false  // リアルタイムキャプチャを使用するか
    var windowFrame: CGRect = .zero  // ウィンドウの画面上の位置（NS座標系、左下原点）
    var windowNumber: Int = 0  // 自分のウィンドウを除外するため
    var canvasSize: CGSize = .zero  // キャンバスサイズ
    private var cachedBlurredImage: NSImage?
    private var cachedRect: CGRect?
    private var cachedWindowFrame: CGRect?

    init(rect: CGRect, pixelSize: Int = 10, sourceImage: NSImage? = nil) {
        self.rect = rect
        self.pixelSize = pixelSize
        self.sourceImage = sourceImage
    }

    func draw(in bounds: NSRect) {
        guard rect.width > 5 && rect.height > 5 else { return }

        // リアルタイムキャプチャモードの場合（一時的に無効化）
        if useRealTimeCapture && windowNumber > 0 {
            drawRealTimeBlur(in: bounds)
        } else if let image = sourceImage {
            // 通常モード：画像があればぼかしプレビューを表示
            // キャッシュが有効か確認
            if cachedBlurredImage == nil || cachedRect != rect {
                cachedBlurredImage = createBlurredPreview(from: image, canvasSize: bounds.size)
                cachedRect = rect
            }

            if let blurred = cachedBlurredImage {
                // ぼかした画像を描画
                blurred.draw(in: rect, from: NSRect(origin: .zero, size: blurred.size), operation: .sourceOver, fraction: 1.0)
            }
        } else {
            // 画像がない場合はグレーで表示
            NSColor.gray.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: rect).fill()
        }

        // ドラッグ中のみ枠線を表示
        if isDrawing {
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2
            borderPath.stroke()

            NSColor.black.setStroke()
            let innerPath = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            innerPath.lineWidth = 1
            innerPath.stroke()
        }
    }

    private func drawRealTimeBlur(in bounds: NSRect) {
        guard rect.width > 5 && rect.height > 5 else { return }
        guard windowNumber > 0 else {
            // ウィンドウ番号がない場合はグレーで表示
            NSColor.gray.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: rect).fill()
            return
        }

        let primaryHeight = NSScreen.primaryScreenHeight

        // キャンバス座標（上左原点）からスクリーン座標（CG座標系、上左原点）への変換
        // 1. rectはキャンバス座標（上左原点、isFlipped=true）
        // 2. windowFrameはNS座標（左下原点）
        // 3. CGWindowListCreateImageはCG座標（上左原点）

        // windowの左上のスクリーン座標（CG座標系）
        let windowTopLeftY_CG = primaryHeight - windowFrame.origin.y - windowFrame.height

        // キャプチャ領域のスクリーン座標（CG座標系）
        let screenRect = CGRect(
            x: windowFrame.origin.x + rect.origin.x,
            y: windowTopLeftY_CG + rect.origin.y,
            width: rect.width,
            height: rect.height
        )

        // キャッシュが有効か確認（位置が変わっていなければ再利用）
        if let cached = cachedBlurredImage,
           cachedRect == rect,
           cachedWindowFrame == windowFrame {
            cached.draw(in: rect, from: NSRect(origin: .zero, size: cached.size), operation: .sourceOver, fraction: 1.0)
            return
        }

        // 自分のウィンドウより下にある画面をキャプチャ
        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenBelowWindow,
            CGWindowID(windowNumber),
            [.bestResolution]
        ) else {
            NSColor.gray.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: rect).fill()
            return
        }

        // キャプチャした画像にぼかしを適用
        let ciImage = CIImage(cgImage: cgImage)

        guard let pixellateFilter = CIFilter(name: "CIPixellate") else { return }
        pixellateFilter.setValue(ciImage, forKey: kCIInputImageKey)
        pixellateFilter.setValue(NSNumber(value: max(pixelSize * 2, 8)), forKey: kCIInputScaleKey)
        pixellateFilter.setValue(CIVector(x: ciImage.extent.midX, y: ciImage.extent.midY), forKey: kCIInputCenterKey)

        guard let outputImage = pixellateFilter.outputImage else { return }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputImage, from: ciImage.extent) else { return }

        let blurredImage = NSImage(cgImage: outputCGImage, size: rect.size)

        // キャッシュを更新
        cachedBlurredImage = blurredImage
        cachedRect = rect
        cachedWindowFrame = windowFrame

        blurredImage.draw(in: rect, from: NSRect(origin: .zero, size: blurredImage.size), operation: .sourceOver, fraction: 1.0)
    }

    private func createBlurredPreview(from image: NSImage, canvasSize: CGSize) -> NSImage? {
        // 画像サイズとキャンバスサイズのスケール計算
        let scale = image.size.width / canvasSize.width

        // キャンバス座標を画像座標に変換
        let imageRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        // 画像座標で切り出し
        let croppedImage = ciImage.cropped(to: imageRect)

        // ピクセル化フィルタ
        guard let pixellateFilter = CIFilter(name: "CIPixellate") else { return nil }
        pixellateFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        pixellateFilter.setValue(NSNumber(value: max(pixelSize * Int(scale), 5)), forKey: kCIInputScaleKey)
        pixellateFilter.setValue(CIVector(x: imageRect.midX, y: imageRect.midY), forKey: kCIInputCenterKey)

        guard let outputImage = pixellateFilter.outputImage else { return nil }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputImage, from: imageRect) else {
            return nil
        }

        // キャンバスサイズに合わせて返す
        return NSImage(cgImage: outputCGImage, size: rect.size)
    }

    func applyBlurToImage(_ image: NSImage, in imageRect: CGRect) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            return image
        }

        let ciImage = CIImage(cgImage: cgImage)

        // 領域を切り出し（Y座標反転なし - プレビューと同じ座標系）
        let croppedImage = ciImage.cropped(to: imageRect)

        // ピクセル化フィルタを適用
        guard let pixellateFilter = CIFilter(name: "CIPixellate") else { return image }
        pixellateFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        pixellateFilter.setValue(NSNumber(value: pixelSize), forKey: kCIInputScaleKey)
        pixellateFilter.setValue(CIVector(x: imageRect.midX, y: imageRect.midY), forKey: kCIInputCenterKey)

        guard let pixellatedCropped = pixellateFilter.outputImage else { return image }

        // 元画像の上にぼかした部分を合成
        let composited = pixellatedCropped.composited(over: ciImage)

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(composited, from: ciImage.extent) else {
            return image
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }

    func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
    }

    func move(by delta: CGPoint) {
        rect = CGRect(x: rect.origin.x + delta.x, y: rect.origin.y + delta.y, width: rect.width, height: rect.height)
        clearCache()
    }

    func clearCache() {
        cachedBlurredImage = nil
        cachedRect = nil
        cachedWindowFrame = nil
    }

    func applyToImage(_ image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return image
        }

        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(pixelSize, forKey: kCIInputScaleKey)

        guard let outputImage = filter?.outputImage else {
            return image
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return image
        }

        return NSImage(cgImage: cgImage, size: image.size)
    }

    // 属性アクセス（ツールボックスから編集可能に）
    var annotationColor: NSColor? {
        get { nil }
        set { }
    }
    var annotationLineWidth: CGFloat? {
        get { CGFloat(pixelSize - 1) / 1.2 }  // 逆算
        set {
            if let w = newValue {
                pixelSize = max(Int(w * 1.2 + 1), 2)
                clearCache()
            }
        }
    }
    var annotationStrokeEnabled: Bool? {
        get { nil }
        set { }
    }
}
