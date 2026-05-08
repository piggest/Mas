import XCTest
import AppKit
@testable import Mas

/// `RegionSelectionOverlay` の経路選択ロジック（AX 権限有無 → CGEventTap or
/// フォールバック）が正しく wiring されていることを保証する回帰テスト。
///
/// `show()` は実際に NSPanel を作成するため、`NSScreen.main` が利用可能な
/// テスト環境（macOS desktop）でのみ動作する。
@MainActor
final class RegionSelectionOverlayWiringTests: XCTestCase {

    /// AX 権限あり → CGEventTap を install する
    func test_show_whenAXTrusted_installsEventTap() {
        let ax = MockAccessibility(trusted: true)
        let tap = MockMouseEventTap(shouldSucceedInstall: true)
        let overlay = RegionSelectionOverlay(
            accessibility: ax,
            eventTap: tap,
            onComplete: { _ in },
            onCancel: nil
        )

        overlay.show()
        defer { overlay.cancelForTest() }

        XCTAssertEqual(tap.installCallCount, 1, "AX 許可ありで eventTap.install が呼ばれるべき")
        XCTAssertEqual(ax.requestCallCount, 0, "既に許可済なので requestAccessibility は呼ばない")
    }

    /// AX 権限なし → install 呼ばず、権限要求を行う
    func test_show_whenAXNotTrusted_doesNotInstallTap_butRequestsPermission() {
        let ax = MockAccessibility(trusted: false)
        let tap = MockMouseEventTap()
        let overlay = RegionSelectionOverlay(
            accessibility: ax,
            eventTap: tap,
            onComplete: { _ in },
            onCancel: nil
        )

        overlay.show()
        defer { overlay.cancelForTest() }

        XCTAssertEqual(tap.installCallCount, 0, "AX 未許可なら eventTap.install を呼ばない")
        XCTAssertEqual(ax.requestCallCount, 1, "未許可なので権限要求を行う")
    }

    /// dismiss 時に eventTap.uninstall が呼ばれる
    func test_dismiss_uninstallsTap() {
        let ax = MockAccessibility(trusted: true)
        let tap = MockMouseEventTap(shouldSucceedInstall: true)
        let overlay = RegionSelectionOverlay(
            accessibility: ax,
            eventTap: tap,
            onComplete: { _ in },
            onCancel: nil
        )

        overlay.show()
        overlay.cancelForTest()

        // install 1 + dismiss 内 uninstall 1 + (再 install 時の安全 uninstall は今回呼ばない)
        XCTAssertGreaterThanOrEqual(tap.uninstallCallCount, 1, "dismiss で uninstall されるべき")
    }

    /// ESC 経由のキャンセル: tap callback で escKeyDown を投げると onCancel が呼ばれる
    func test_escKeyDownEvent_triggersCancel() {
        let ax = MockAccessibility(trusted: true)
        let tap = MockMouseEventTap(shouldSucceedInstall: true)
        var cancelCalled = false
        let overlay = RegionSelectionOverlay(
            accessibility: ax,
            eventTap: tap,
            onComplete: { _ in XCTFail("ESC 経由では onComplete を呼ばない") },
            onCancel: { cancelCalled = true }
        )

        overlay.show()
        tap.simulate(.escKeyDown)

        // tap callback は main async で dispatch されるため、少し待つ
        let exp = expectation(description: "ESC キャンセル")
        DispatchQueue.main.async {
            XCTAssertTrue(cancelCalled, "ESC で onCancel が呼ばれるべき")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
