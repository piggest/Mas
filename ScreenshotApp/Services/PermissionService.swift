import AppKit
import CoreGraphics

@MainActor
class PermissionService {

    /// 画面録画の許可があるかチェック（CGWindowListを使用 - ダイアログを出さない）
    func hasScreenCapturePermission() -> Bool {
        // CGWindowListCopyWindowInfoは許可ダイアログを出さない
        // ウィンドウリストが取得できれば許可されている可能性が高い
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return !windowList.isEmpty
    }

    /// 許可がない場合にユーザーに説明してシステム設定を開く
    func requestScreenCapturePermission() async {
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "スクリーンショットを撮影するには、システム設定で画面収録の許可が必要です。\n\n設定を開いて「Mas」を許可した後、アプリを再起動してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "キャンセル")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemPreferences()
        }
    }

    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
