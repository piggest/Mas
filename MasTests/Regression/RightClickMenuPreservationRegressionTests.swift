import XCTest
import AppKit
@testable import Mas

/// 範囲選択キャプチャ起動時に他アプリの右クリックメニューが消えていたバグの回帰テスト。
///
/// 経緯（v4.2.1 まで）:
/// `RegionSelectionOverlay` が `NSWindow` (`KeyableWindow`) と
/// `NSApp.activate(ignoringOtherApps: true)` を組み合わせて表示していたため、
/// オーバーレイ起動時に Mas が active app に切り替わり、Finder/Unity 等で開いている
/// 右クリックメニュー（NSMenu）が macOS 仕様で即座に dismiss されていた。
/// macOS 標準の `⌘⇧4` は non-activating panel を使ってフォーカスを奪わないため、
/// この問題は発生しない。
///
/// 修正:
/// `OverlayWindowFactory` で `NSPanel` + `.nonactivatingPanel` を生成し、
/// `NSApp.activate(ignoringOtherApps:)` の呼び出しを削除した。
/// これにより active app の切替が起こらず、他アプリの右クリックメニューが残る。
///
/// このテストはオーバーレイ panel の構成が「他アプリのメニューを保つ要件」を
/// 満たしていることを保証する。実際のメニュー dismiss は OS 側の挙動なので、
/// パネル設定が正しいことのみを検証する（クロスアプリの実機検証は手動で行う）。
final class RightClickMenuPreservationRegressionTests: XCTestCase {

    private func makePanel() -> NSPanel {
        guard let screen = NSScreen.main else {
            XCTFail("NSScreen.main not available")
            fatalError()
        }
        return OverlayWindowFactory.makeOverlayPanel(for: screen)
    }

    /// non-activating panel であること。これがないと表示時に active app が切り替わり、
    /// 他アプリの NSMenu が dismiss される。
    func test_overlayPanel_isNonActivating_toPreserveOtherAppMenus() {
        let panel = makePanel()
        XCTAssertTrue(
            panel.styleMask.contains(.nonactivatingPanel),
            ".nonactivatingPanel が外れると右クリックメニュー dismiss バグが再発する"
        )
    }

    /// main window にならないこと。main 化も active app 切替を引き起こす。
    func test_overlayPanel_doesNotBecomeMain_toPreserveOtherAppMenus() {
        let panel = makePanel()
        XCTAssertFalse(
            panel.canBecomeMain,
            "canBecomeMain = true にすると active app が切り替わり右クリックメニューが消える"
        )
    }

    /// `hidesOnDeactivate = false` であること。Mas が他アプリにフォーカス譲渡した場合でも
    /// オーバーレイは表示され続ける必要がある（非アクティブ状態でキャプチャを継続するため）。
    func test_overlayPanel_doesNotHideOnDeactivate() {
        let panel = makePanel()
        XCTAssertFalse(
            panel.hidesOnDeactivate,
            "他アプリがアクティブのままでもオーバーレイを保持するため hidesOnDeactivate = false"
        )
    }
}
