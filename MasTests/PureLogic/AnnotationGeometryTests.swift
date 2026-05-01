import XCTest
@testable import Mas

final class AnnotationGeometryTests: XCTestCase {

    func test_resizedRect_topLeft_movesOriginAndShrinksSize() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .topLeft, to: CGPoint(x: 150, y: 150))
        XCTAssertEqual(resized.origin.x, 150)
        XCTAssertEqual(resized.origin.y, 150)
        XCTAssertEqual(resized.width, 150)
        XCTAssertEqual(resized.height, 150)
    }

    func test_resizedRect_bottomRight_growsSizeOnly() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .bottomRight, to: CGPoint(x: 400, y: 400))
        XCTAssertEqual(resized.origin.x, 100)
        XCTAssertEqual(resized.origin.y, 100)
        XCTAssertEqual(resized.width, 300)
        XCTAssertEqual(resized.height, 300)
    }

    func test_resizedRect_top_changesYAndHeight() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .top, to: CGPoint(x: 150, y: 50))
        XCTAssertEqual(resized.origin.x, 100)
        XCTAssertEqual(resized.origin.y, 50)
        XCTAssertEqual(resized.width, 200)
        XCTAssertEqual(resized.height, 250)
    }

    func test_squareConstrainedResizePoint_topLeftEqualSizes() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let constrained = AnnotationGeometry.squareConstrainedResizePoint(
            point: CGPoint(x: 50, y: 80),
            original: original,
            handle: .topLeft
        )
        XCTAssertEqual(constrained.x, 50)
        XCTAssertEqual(constrained.y, -150)
    }

    func test_lineBoundingRect_includesBothEndpoints() {
        let rect = AnnotationGeometry.lineBoundingRect(
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 300, y: 50),
            lineWidth: 4
        )
        XCTAssertLessThanOrEqual(rect.minX, 100)
        XCTAssertLessThanOrEqual(rect.minY, 50)
        XCTAssertGreaterThanOrEqual(rect.maxX, 300)
        XCTAssertGreaterThanOrEqual(rect.maxY, 200)
    }
}
