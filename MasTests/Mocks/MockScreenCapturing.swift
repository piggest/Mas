import AppKit
import CoreGraphics
@testable import Mas

/// captureScreen 呼び出しを記録し、事前設定した CGImage を返す Mock。
final class MockScreenCapturing: ScreenCapturing {

    /// captureScreen が呼ばれたときに返す画像。
    var stubImage: CGImage

    /// captureScreen が呼ばれた回数。
    private(set) var captureScreenCallCount: Int = 0

    /// captureScreen に渡された screen の履歴。
    private(set) var capturedScreens: [NSScreen] = []

    init(stubImage: CGImage) {
        self.stubImage = stubImage
    }

    func captureScreen(_ screen: NSScreen) async throws -> CGImage {
        captureScreenCallCount += 1
        capturedScreens.append(screen)
        return stubImage
    }
}

extension MockScreenCapturing {
    /// テスト用に単色の CGImage を作る簡易ファクトリ。
    static func makeSolidImage(width: Int, height: Int, color: CGColor = CGColor(gray: 0.5, alpha: 1.0)) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
