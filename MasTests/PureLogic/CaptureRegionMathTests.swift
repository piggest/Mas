import XCTest
@testable import Mas

final class CaptureRegionMathTests: XCTestCase {

    func test_windowFrameToCaptureRegion_convertsNSToCG() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
        let primaryHeight: CGFloat = 1117
        let region = CaptureRegionMath.windowFrameToCaptureRegion(nsFrame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(region, CGRect(x: 100, y: 517, width: 300, height: 400))
    }

    func test_clampedWindowFrame_fitsInsideScreen() {
        let proposed = CGRect(x: 100, y: 100, width: 500, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped, proposed)
    }

    func test_clampedWindowFrame_clipsToScreenWhenOversized() {
        let proposed = CGRect(x: 100, y: 100, width: 5000, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped.width, 1728)
        XCTAssertEqual(clamped.origin.x, 0)
    }

    func test_clampedWindowFrame_shiftsLeftWhenExceedsRightEdge() {
        let proposed = CGRect(x: 1500, y: 100, width: 500, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped.origin.x, 1228)
        XCTAssertEqual(clamped.width, 500)
    }

    func test_initialContentScale_imageFitsInScreen() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 800, height: 600),
            screenVisibleSize: CGSize(width: 1728, height: 1117)
        )
        XCTAssertEqual(scale, 1.0)
    }

    func test_initialContentScale_imageWiderThanScreenScalesDown() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 3000, height: 600),
            screenVisibleSize: CGSize(width: 1500, height: 1117)
        )
        XCTAssertEqual(scale, 0.5)
    }

    func test_initialContentScale_imageTallerThanScreenScalesDown() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 800, height: 2000),
            screenVisibleSize: CGSize(width: 1728, height: 1000)
        )
        XCTAssertEqual(scale, 0.5)
    }

    func test_initialContentScale_zeroSizeReturnsOne() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 0, height: 0),
            screenVisibleSize: CGSize(width: 1728, height: 1117)
        )
        XCTAssertEqual(scale, 1.0)
    }
}
