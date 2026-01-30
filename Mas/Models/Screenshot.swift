import AppKit
import Foundation

class Screenshot: ObservableObject, Identifiable {
    let id = UUID()
    @Published var originalImage: NSImage
    @Published var annotations: [any Annotation] = []
    let capturedAt: Date
    let mode: CaptureMode
    var captureRegion: CGRect?  // 範囲選択時の領域（スクリーン座標）

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
        let finalImage = NSImage(size: size)

        finalImage.lockFocus()

        originalImage.draw(in: NSRect(origin: .zero, size: size))

        for annotation in annotations {
            annotation.draw(in: NSRect(origin: .zero, size: size))
        }

        finalImage.unlockFocus()

        return finalImage
    }
}
