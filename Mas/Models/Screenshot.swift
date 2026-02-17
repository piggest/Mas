import AppKit
import Foundation

class Screenshot: ObservableObject, Identifiable {
    let id = UUID()
    @Published var originalImage: NSImage
    @Published var annotations: [any Annotation] = []
    let capturedAt: Date
    let mode: CaptureMode
    var captureRegion: CGRect?  // 範囲選択時の領域（スクリーン座標）
    var savedURL: URL?  // 保存先URL（上書き用）
    var isGif: Bool { mode == .gifRecording && savedURL?.pathExtension.lowercased() == "gif" }

    init(image: NSImage, mode: CaptureMode, region: CGRect? = nil) {
        self.originalImage = image
        self.capturedAt = Date()
        self.mode = mode
        self.captureRegion = region
    }

    convenience init(cgImage: CGImage, mode: CaptureMode, region: CGRect? = nil) {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        self.init(image: nsImage, mode: mode, region: region)
    }

    func updateImage(_ cgImage: CGImage) {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        self.originalImage = NSImage(cgImage: cgImage, size: size)
    }

    func renderFinalImage() -> NSImage {
        let size = originalImage.size

        // アノテーションのはみ出しを含む拡張サイズを計算
        var expandedRect = CGRect(origin: .zero, size: size)
        for annotation in annotations {
            expandedRect = expandedRect.union(annotation.boundingRect())
        }
        let offset = CGPoint(x: -expandedRect.origin.x, y: -expandedRect.origin.y)
        let expandedSize = NSSize(width: expandedRect.width, height: expandedRect.height)

        let finalImage = NSImage(size: expandedSize)
        finalImage.lockFocus()

        // はみ出し領域を白で塗りつぶし
        if expandedSize != size {
            NSColor.white.setFill()
            NSRect(origin: .zero, size: expandedSize).fill()
        }

        originalImage.draw(in: NSRect(origin: CGPoint(x: offset.x, y: offset.y), size: size))

        // アノテーションをオフセット付きで描画
        if offset == .zero {
            for annotation in annotations {
                annotation.draw(in: NSRect(origin: .zero, size: expandedSize))
            }
        } else {
            NSGraphicsContext.current?.cgContext.translateBy(x: offset.x, y: offset.y)
            for annotation in annotations {
                annotation.draw(in: NSRect(origin: .zero, size: size))
            }
            NSGraphicsContext.current?.cgContext.translateBy(x: -offset.x, y: -offset.y)
        }

        finalImage.unlockFocus()

        return finalImage
    }
}
