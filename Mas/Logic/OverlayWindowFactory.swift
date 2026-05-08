import AppKit

/// 範囲選択オーバーレイ用の NSPanel を生成するファクトリ。
///
/// 旧実装 (`KeyableWindow: NSWindow` + `NSApp.activate(ignoringOtherApps:)`) では
/// オーバーレイ表示時に Mas が active app へ切り替わり、他アプリで開いている
/// NSMenu（右クリックメニュー）が macOS によって即座に dismiss されていた。
///
/// 修正: `NSPanel` に `.nonactivatingPanel` スタイルマスクを付与することで、
/// アクティブアプリ切替を起こさずにオーバーレイを前面表示する。
/// 他アプリの右クリックメニューを残したままキャプチャできる。
enum OverlayWindowFactory {

    /// 指定スクリーン全体を覆う non-activating panel を生成する。
    ///
    /// - Parameter screen: 対象のスクリーン（マルチディスプレイで各スクリーン分作成する）
    /// - Returns: フォーカスを奪わずにオーバーレイ表示できる `NSPanel`
    static func makeOverlayPanel(for screen: NSScreen) -> NSPanel {
        let panel = NonActivatingOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 開いている NSMenu（右クリックメニュー）よりも上に置かないと、
        // ドラッグ時にマウスイベントが menu に届いて dismiss されてしまう。
        // popUpMenu(101) では足りないケースがあるため screenSaver(1000) レベルを使う。
        // パネルは透過なので、メニューの内容は引き続き視認できる。
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = NSWindow.masSharingType
        panel.hidesOnDeactivate = false
        return panel
    }
}

/// ESC キーを受信するため key にはなれるが、main にはならないパネル。
/// main にしないことで他アプリのアクティブ状態（および開かれた NSMenu）を保つ。
private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
