import XCTest
@testable import Mas

final class CropMathTests: XCTestCase {

    func test_scaledRect_primaryScreenRetinaScale2() {
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let screenCGFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let scaled = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: 2.0)
        XCTAssertEqual(scaled, CGRect(x: 200, y: 400, width: 800, height: 600))
    }

    func test_scaledRect_secondaryScreenWithNegativeOrigin() {
        let region = CGRect(x: -1500, y: 100, width: 200, height: 200)
        let screenCGFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let scaled = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: 1.0)
        XCTAssertEqual(scaled, CGRect(x: 420, y: 100, width: 200, height: 200))
    }

    func test_clampedRect_fullyInside() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertEqual(clamped, rect)
    }

    func test_clampedRect_partialOutsideClipsToImage() {
        let rect = CGRect(x: 900, y: 900, width: 200, height: 200)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertEqual(clamped, CGRect(x: 900, y: 900, width: 100, height: 100))
    }

    func test_clampedRect_completelyOutsideReturnsEmpty() {
        let rect = CGRect(x: 2000, y: 2000, width: 100, height: 100)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertTrue(clamped.isEmpty)
    }

    func test_imageScale_isImageWidthDividedByScreenWidth() {
        let scale = CropMath.imageScale(imageWidth: 3456, screenWidth: 1728)
        XCTAssertEqual(scale, 2.0)
    }
}
