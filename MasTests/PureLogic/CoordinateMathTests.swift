import XCTest
@testable import Mas

final class CoordinateMathTests: XCTestCase {

    func test_nsToCG_originIsSymmetric() {
        let primaryHeight: CGFloat = 1080
        let nsRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let cgRect = CoordinateMath.nsToCG(nsRect, primaryHeight: primaryHeight)
        XCTAssertEqual(cgRect.origin.x, 0)
        XCTAssertEqual(cgRect.origin.y, 980)
        XCTAssertEqual(cgRect.width, 100)
        XCTAssertEqual(cgRect.height, 100)
    }

    func test_cgToNS_isInverseOfNsToCG() {
        let primaryHeight: CGFloat = 1117
        let original = CGRect(x: 200, y: 300, width: 400, height: 500)
        let cg = CoordinateMath.nsToCG(original, primaryHeight: primaryHeight)
        let backToNs = CoordinateMath.cgToNS(cg, primaryHeight: primaryHeight)
        XCTAssertEqual(backToNs.origin.x, original.origin.x, accuracy: 0.0001)
        XCTAssertEqual(backToNs.origin.y, original.origin.y, accuracy: 0.0001)
        XCTAssertEqual(backToNs.width, original.width, accuracy: 0.0001)
        XCTAssertEqual(backToNs.height, original.height, accuracy: 0.0001)
    }

    func test_cgFrameForScreen_primaryScreenOriginIsZero() {
        let nsFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let primaryHeight: CGFloat = 1117
        let cg = CoordinateMath.cgFrameForScreen(nsFrame: nsFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(cg, CGRect(x: 0, y: 0, width: 1728, height: 1117))
    }

    func test_cgFrameForScreen_secondaryAboveOnly() {
        let nsFrame = CGRect(x: 0, y: 1117, width: 1920, height: 1080)
        let primaryHeight: CGFloat = 1117
        let cg = CoordinateMath.cgFrameForScreen(nsFrame: nsFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(cg.origin.x, 0)
        XCTAssertEqual(cg.origin.y, -1080)
        XCTAssertEqual(cg.width, 1920)
        XCTAssertEqual(cg.height, 1080)
    }

    func test_nsToCG_negativeOriginX() {
        let primaryHeight: CGFloat = 1117
        let nsRect = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let cg = CoordinateMath.nsToCG(nsRect, primaryHeight: primaryHeight)
        XCTAssertEqual(cg.origin.x, -1920)
        XCTAssertEqual(cg.origin.y, 37)
    }
}
