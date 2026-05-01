import XCTest
@testable import Mas

/// 既存の AnnotationCanvas 挙動を維持していることを検証するテスト。
/// 期待値は既存実装の出力に完全一致させている（挙動同等のリファクタなので新規挙動を作らない）。
final class AnnotationGeometryTests: XCTestCase {

    // MARK: - resizedRect

    func test_resizedRect_topLeft_existingBehavior() {
        // 既存: x=point.x, y=original.minY, width=original.maxX-point.x, height=point.y-original.minY
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .topLeft,
            to: CGPoint(x: 150, y: 150)
        )
        XCTAssertEqual(resized, CGRect(x: 150, y: 100, width: 150, height: 50))
    }

    func test_resizedRect_topRight_existingBehavior() {
        // 既存: x=original.minX, y=original.minY, width=point.x-original.minX, height=point.y-original.minY
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .topRight,
            to: CGPoint(x: 350, y: 250)
        )
        XCTAssertEqual(resized, CGRect(x: 100, y: 100, width: 250, height: 150))
    }

    func test_resizedRect_bottomLeft_existingBehavior() {
        // 既存: x=point.x, y=point.y, width=original.maxX-point.x, height=original.maxY-point.y
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .bottomLeft,
            to: CGPoint(x: 50, y: 80)
        )
        // newRect = (50, 80, 250, 220). all >= minSize(10), 正規化なし
        XCTAssertEqual(resized, CGRect(x: 50, y: 80, width: 250, height: 220))
    }

    func test_resizedRect_bottomRight_negativeHeightNormalizedToMinSize() {
        // 既存挙動: bottomRight で point.y > original.maxY のとき height が負になり minSize ガードで正規化される。
        // CGRect の minY/maxY は Swift 標準では origin.y を基準に返すため、
        // 正規化後の origin.y = origin.y(=400) になる（既存実装の挙動を維持）。
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .bottomRight,
            to: CGPoint(x: 400, y: 400)
        )
        XCTAssertEqual(resized.width, 300)
        XCTAssertEqual(resized.height, 100)
    }

    func test_resizedRect_minSizeGuard_widthBelowThreshold() {
        // 幅 = 300 - 295 = 5 < 10 で正規化される
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .topRight,
            to: CGPoint(x: 105, y: 250)
        )
        // newRect = (100, 100, 5, 150) → width<10 で正規化
        // 正規化: x=min(100,105)=100, y=min(100,250)=100, width=max(5,10)=10, height=max(150,10)=150
        XCTAssertEqual(resized.width, 10)
        XCTAssertEqual(resized.height, 150)
    }

    func test_resizedRect_noneHandleReturnsOriginal() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(
            original: original,
            handle: .none,
            to: CGPoint(x: 999, y: 999)
        )
        XCTAssertEqual(resized, original)
    }

    // MARK: - squareConstrainedResizePoint

    func test_squareConstrained_topLeft_dxLargerThanDy() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        // anchor (topLeft) = (maxX=300, minY=100)
        // point (50, 80): dx=-250, dy=-20, size=max(250,20)=250
        // result = (300 + (-250), 100 + (-250)) = (50, -150)
        let constrained = AnnotationGeometry.squareConstrainedResizePoint(
            point: CGPoint(x: 50, y: 80),
            original: original,
            handle: .topLeft
        )
        XCTAssertEqual(constrained.x, 50)
        XCTAssertEqual(constrained.y, -150)
    }

    func test_squareConstrained_bottomRight_dxEqualsDy() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        // anchor (bottomRight) = (minX=100, maxY=300)
        // point (200, 400): dx=100, dy=100, size=100
        // result = (100 + 100, 300 + 100) = (200, 400)
        let constrained = AnnotationGeometry.squareConstrainedResizePoint(
            point: CGPoint(x: 200, y: 400),
            original: original,
            handle: .bottomRight
        )
        XCTAssertEqual(constrained.x, 200)
        XCTAssertEqual(constrained.y, 400)
    }

    func test_squareConstrained_unsupportedHandleReturnsPoint() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let p = CGPoint(x: 50, y: 60)
        let constrained = AnnotationGeometry.squareConstrainedResizePoint(
            point: p,
            original: original,
            handle: .startPoint
        )
        XCTAssertEqual(constrained, p)
    }

    // MARK: - lineBoundingRect

    func test_lineBoundingRect_paddingExpandsAllSides() {
        let rect = AnnotationGeometry.lineBoundingRect(
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 300, y: 50),
            padding: 6
        )
        XCTAssertEqual(rect.minX, 94)
        XCTAssertEqual(rect.minY, 44)
        XCTAssertEqual(rect.maxX, 306)
        XCTAssertEqual(rect.maxY, 206)
    }

    func test_lineBoundingRect_zeroPaddingMatchesEndpoints() {
        let rect = AnnotationGeometry.lineBoundingRect(
            startPoint: CGPoint(x: 100, y: 100),
            endPoint: CGPoint(x: 200, y: 300),
            padding: 0
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 100, height: 200))
    }
}
