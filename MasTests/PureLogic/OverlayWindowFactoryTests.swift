import XCTest
import AppKit
@testable import Mas

/// 範囲選択オーバーレイのウィンドウ構成をテストする。
///
/// 背景: 旧実装は NSWindow + NSApp.activate(ignoringOtherApps:) を使っており、
/// オーバーレイ起動時に Mas が active app に切り替わるため、他アプリで開いている
/// NSMenu（右クリックメニュー）が macOS によって即座に dismiss されてしまっていた。
///
/// 修正方針: NSPanel に .nonactivatingPanel スタイルを付け、active app を切り替えずに
/// オーバーレイを表示する。これにより他アプリの NSMenu が残ったままキャプチャできる。
final class OverlayWindowFactoryTests: XCTestCase {

    private func makePanel() -> NSPanel {
        guard let screen = NSScreen.main else {
            XCTFail("NSScreen.main not available in test environment")
            fatalError()
        }
        return OverlayWindowFactory.makeOverlayPanel(for: screen)
    }

    func test_factory_returnsNSPanel() {
        let panel = makePanel()
        // NSPanel であること（NSWindow ではなく）
        XCTAssertTrue(panel is NSPanel, "NSPanel を返すべき。NSWindow では .nonactivatingPanel が機能しない")
    }

    func test_panel_hasNonActivatingStyleMask() {
        let panel = makePanel()
        XCTAssertTrue(
            panel.styleMask.contains(.nonactivatingPanel),
            ".nonactivatingPanel が必須。これがないと表示時に他アプリの右クリックメニューが dismiss される"
        )
    }

    func test_panel_isBorderless() {
        let panel = makePanel()
        XCTAssertTrue(panel.styleMask.contains(.borderless), "オーバーレイは枠なし")
    }

    func test_panel_canBecomeKey_forESCKeyHandling() {
        let panel = makePanel()
        // キーイベント（ESC キャンセル）を受信するため key になれる必要がある
        XCTAssertTrue(panel.canBecomeKey, "ESC キーでキャンセルするため key になれる必要がある")
    }

    func test_panel_doesNotBecomeMain() {
        let panel = makePanel()
        // main window にはならない（他アプリのアクティブ状態を保つため）
        XCTAssertFalse(panel.canBecomeMain, "main window にはならない（active app の切替を発生させない）")
    }

    func test_panel_levelIsAbovePopUpMenu() {
        let panel = makePanel()
        // NSMenu (右クリックメニュー) は .popUpMenu レベルで描画される。
        // それより上に乗せないとマウスイベントが menu に届き、ドラッグ開始で
        // メニューが dismiss されてしまう。
        XCTAssertGreaterThan(
            panel.level.rawValue,
            NSWindow.Level.popUpMenu.rawValue,
            "popUpMenu レベルより上に置かないと NSMenu の上にマウスイベントが届かない"
        )
    }

    func test_panel_isTransparentForOverlay() {
        let panel = makePanel()
        XCTAssertFalse(panel.isOpaque, "選択範囲以外を透過させるため opaque ではない")
        XCTAssertEqual(panel.backgroundColor, .clear, "背景色は透明")
        XCTAssertFalse(panel.hasShadow, "影は不要")
    }

    func test_panel_acceptsMouseEvents() {
        let panel = makePanel()
        XCTAssertFalse(panel.ignoresMouseEvents, "ドラッグで範囲選択するためマウスイベントを受信する")
        XCTAssertTrue(panel.acceptsMouseMovedEvents, "mouseMoved を受信して選択中の表示を更新する")
    }

    func test_panel_appearsOnAllSpacesAndFullScreen() {
        let panel = makePanel()
        XCTAssertTrue(
            panel.collectionBehavior.contains(.canJoinAllSpaces),
            "全スペースで表示できるべき"
        )
        XCTAssertTrue(
            panel.collectionBehavior.contains(.fullScreenAuxiliary),
            "フルスクリーンアプリの上にも表示できるべき"
        )
    }

    func test_panel_isHiddenFromOwnCapture() {
        let panel = makePanel()
        XCTAssertEqual(
            panel.sharingType,
            NSWindow.masSharingType,
            "Mas 自身のキャプチャ対象から除外するため共通の sharingType を使う"
        )
    }

    func test_panel_doesNotHideOnDeactivate() {
        let panel = makePanel()
        XCTAssertFalse(
            panel.hidesOnDeactivate,
            "他アプリがアクティブのままでも表示し続けるため hidesOnDeactivate = false"
        )
    }

    func test_panel_frameMatchesScreen() {
        guard let screen = NSScreen.main else { fatalError() }
        let panel = OverlayWindowFactory.makeOverlayPanel(for: screen)
        XCTAssertEqual(panel.frame, screen.frame, "パネルはスクリーン全体を覆う")
    }
}
