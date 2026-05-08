import Foundation
@testable import Mas

/// アクセシビリティ権限をテストで制御するためのモック。
final class MockAccessibility: AccessibilityChecking {
    var trusted: Bool
    var requestCallCount = 0
    var openSettingsCallCount = 0

    init(trusted: Bool) {
        self.trusted = trusted
    }

    func isTrusted() -> Bool {
        return trusted
    }

    func requestAccessibility() -> Bool {
        requestCallCount += 1
        return trusted
    }

    func openAccessibilitySettings() {
        openSettingsCallCount += 1
    }
}
