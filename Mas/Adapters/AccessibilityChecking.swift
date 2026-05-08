import AppKit
import ApplicationServices

/// アクセシビリティ権限の有無を確認するプロトコル。
///
/// `CGEventTap` でグローバルマウスイベントを横取りするには、
/// アクセシビリティ権限（System Settings → Privacy & Security → Accessibility）が
/// 必須。プロトコル経由にしてテストでモック差し替え可能にしている。
protocol AccessibilityChecking {
    /// 現在アクセシビリティ権限が許可されているかを返す。
    func isTrusted() -> Bool

    /// 未許可の場合、システムの権限ダイアログを表示しつつ現在の状態を返す。
    /// ダイアログは非同期で開かれるため、即座に true は返らない。
    func requestAccessibility() -> Bool

    /// システム設定のアクセシビリティ画面を開く。
    func openAccessibilitySettings()
}

/// 本番用の実装。AXIsProcessTrusted / AXIsProcessTrustedWithOptions を呼ぶ。
struct SystemAccessibility: AccessibilityChecking {
    func isTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        // System Settings の Privacy & Security → Accessibility を直接開く URL スキーム
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
