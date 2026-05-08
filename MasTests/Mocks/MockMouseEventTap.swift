import Foundation
@testable import Mas

/// テスト用のマウスイベントタップ。CGEventTap を実際には作成せず、
/// `simulate(_:)` で任意のイベントを注入できる。
final class MockMouseEventTap: MouseEventTapping {
    /// `install` を成功させるか。AX 権限がない状況をシミュレートする場合は false。
    var shouldSucceedInstall: Bool

    private(set) var installCallCount = 0
    private(set) var uninstallCallCount = 0
    private var handler: ((MouseEventTapEvent) -> Void)?

    init(shouldSucceedInstall: Bool = true) {
        self.shouldSucceedInstall = shouldSucceedInstall
    }

    func install(handler: @escaping (MouseEventTapEvent) -> Void) -> Bool {
        installCallCount += 1
        guard shouldSucceedInstall else { return false }
        self.handler = handler
        return true
    }

    func uninstall() {
        uninstallCallCount += 1
        handler = nil
    }

    /// テストからイベントを注入する。
    func simulate(_ event: MouseEventTapEvent) {
        handler?(event)
    }
}
