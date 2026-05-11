import XCTest
import AppKit
@testable import Mas

/// ClipboardService の基本動作テスト。
/// NSPasteboard.general を直接触るためテスト同士でクリップボードを共有してしまうが、
/// 各テストで一意な文字列を書き込んで読み戻すので相互干渉はしない。
final class ClipboardServiceTests: XCTestCase {

    func test_copyString_writesToPasteboard() {
        let service = ClipboardService()
        let unique = "Mas-clipboard-test-\(UUID().uuidString)"

        let ok = service.copyToClipboard(string: unique)

        XCTAssertTrue(ok, "コピー成功を返すべき")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), unique)
    }

    func test_copyString_overwritesPreviousContent() {
        let service = ClipboardService()
        _ = service.copyToClipboard(string: "first-\(UUID().uuidString)")

        let second = "second-\(UUID().uuidString)"
        _ = service.copyToClipboard(string: second)

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            second,
            "後に呼んだ文字列で上書きされるべき"
        )
    }

    func test_copyString_emptyStringIsAllowed() {
        let service = ClipboardService()
        let ok = service.copyToClipboard(string: "")
        XCTAssertTrue(ok, "空文字列もコピー可能")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "")
    }
}
