import XCTest
@testable import Mas

final class SmokeTests: XCTestCase {
    func test_smoke_basic_assertion_passes() {
        XCTAssertEqual(1 + 1, 2)
    }
}
