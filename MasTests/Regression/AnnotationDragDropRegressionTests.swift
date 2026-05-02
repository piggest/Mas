import XCTest
import AppKit
@testable import Mas

/// 29d9f09 「Fix annotations not applied during drag & drop」回帰テスト。
/// `Screenshot.renderFinalImage()` がアノテーションを正しく焼き付けることを検証する。
final class AnnotationDragDropRegressionTests: XCTestCase {

    /// テスト用の単色 NSImage を作る。
    private func makeStubImage(width: Int, height: Int, color: NSColor = .white) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    func test_renderFinalImage_withoutAnnotations_returnsOriginalSize() {
        let image = makeStubImage(width: 200, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        let final = screenshot.renderFinalImage()
        XCTAssertEqual(final.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(final.size.height, 100, accuracy: 0.5)
    }

    func test_renderFinalImage_withAnnotationInsideBounds_keepsOriginalSize() {
        let image = makeStubImage(width: 400, height: 300)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        // 画像内に収まる矩形アノテーションを追加
        let rectAnnotation = RectAnnotation(
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red,
            lineWidth: 3
        )
        screenshot.annotations = [rectAnnotation]

        let final = screenshot.renderFinalImage()
        // アノテーションが画像内なら、最終サイズは元と同じ
        XCTAssertEqual(final.size.width, 400, accuracy: 0.5)
        XCTAssertEqual(final.size.height, 300, accuracy: 0.5)
    }

    func test_renderFinalImage_withAnnotationOverflowingBounds_expandsImage() {
        let image = makeStubImage(width: 100, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        // 画像外に大きくはみ出す矩形アノテーション
        let rectAnnotation = RectAnnotation(
            rect: CGRect(x: -50, y: -50, width: 300, height: 300),
            color: .red,
            lineWidth: 3
        )
        screenshot.annotations = [rectAnnotation]

        let final = screenshot.renderFinalImage()
        // アノテーションがはみ出した分だけ画像サイズが拡張される
        XCTAssertGreaterThan(final.size.width, 100)
        XCTAssertGreaterThan(final.size.height, 100)
    }

    func test_renderFinalImage_returnsNonEmptyImage() {
        let image = makeStubImage(width: 200, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        let final = screenshot.renderFinalImage()
        // 戻り値が valid な画像であること（size が 0 でない）
        XCTAssertGreaterThan(final.size.width, 0)
        XCTAssertGreaterThan(final.size.height, 0)
    }
}
