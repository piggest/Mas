import AppKit
import Foundation
import CoreImage

class MosaicAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var pixelSize: Int
    var sourceImage: NSImage?
    var isDrawing: Bool = true  // ドラッグ中かどうか
    private var cachedBlurredImage: NSImage?
    private var cachedRect: CGRect?

    init(rect: CGRect, pixelSize: Int = 10, sourceImage: NSImage? = nil) {
        self.rect = rect
        self.pixelSize = pixelSize
        self.sourceImage = sourceImage
    }

    func draw(in bounds: NSRect) {
        guard rect.width > 5 && rect.height > 5 else { return }

        // 画像があればぼかしプレビューを表示
        if let image = sourceImage {
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
        // キャッシュをクリア
        cachedBlurredImage = nil
        cachedRect = nil
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
}
