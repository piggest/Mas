import CoreGraphics

/// NS 座標系（左下原点）と CG 座標系（左上原点）の純粋計算。
/// AppKit/UIKit に依存しない値型のみで完結する。
enum CoordinateMath {

    /// NS 矩形を CG 矩形に変換する。primaryHeight は NSScreen.screens[0].frame.height。
    static func nsToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// CG 矩形を NS 矩形に変換する。
    static func cgToNS(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// スクリーン NS frame から CG frame を計算する。
    static func cgFrameForScreen(nsFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        nsToCG(nsFrame, primaryHeight: primaryHeight)
    }
}
