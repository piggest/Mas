import AppKit
import Foundation
import CoreImage

class MosaicAnnotation: Annotation {
    let id = UUID()
    var rect: CGRect
    var pixelSize: Int

    init(rect: CGRect, pixelSize: Int = 10) {
        self.rect = rect
        self.pixelSize = pixelSize
    }

    func draw(in bounds: NSRect) {
        NSColor.gray.withAlphaComponent(0.5).setFill()

        let gridSize = CGFloat(pixelSize)
        for x in stride(from: rect.minX, to: rect.maxX, by: gridSize) {
            for y in stride(from: rect.minY, to: rect.maxY, by: gridSize) {
                let cellRect = CGRect(x: x, y: y, width: gridSize, height: gridSize)
                let clippedRect = cellRect.intersection(rect)

                let brightness = ((Int(x) / pixelSize + Int(y) / pixelSize) % 2 == 0) ? 0.3 : 0.5
                NSColor.gray.withAlphaComponent(brightness).setFill()
                NSBezierPath(rect: clippedRect).fill()
            }
        }
    }

    func contains(point: CGPoint) -> Bool {
        return rect.contains(point)
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
