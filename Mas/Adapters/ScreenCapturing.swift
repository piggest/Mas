import AppKit
import CoreGraphics

/// 画面キャプチャを抽象化するプロトコル。テストでは Mock を注入する。
protocol ScreenCapturing {
    func captureScreen(_ screen: NSScreen) async throws -> CGImage
}
