import CoreGraphics

/// キャプチャ枠ウィンドウに関する純粋計算。
/// `window.frame` ↔ CG region 変換、画面に収めるためのウィンドウサイズ調整、
/// コンテンツスケールの初期計算など。
enum CaptureRegionMath {

    /// NS 座標のウィンドウフレームを CG 座標のキャプチャ region に変換。
    static func windowFrameToCaptureRegion(nsFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CoordinateMath.nsToCG(nsFrame, primaryHeight: primaryHeight)
    }

    /// 提案されたウィンドウフレームを画面の可視領域内に収まるよう調整する。
    /// 元のサイズが画面より大きければ画面サイズに丸め、位置がはみ出していれば画面端に押し込む（端揃え）。
    static func clampedWindowFrame(proposed: CGRect, screenVisibleFrame: CGRect) -> CGRect {
        let newWidth = min(proposed.width, screenVisibleFrame.width)
        let newHeight = min(proposed.height, screenVisibleFrame.height)
        let newX = max(
            screenVisibleFrame.minX,
            min(proposed.origin.x, screenVisibleFrame.maxX - newWidth)
        )
        let newY = max(
            screenVisibleFrame.minY,
            min(proposed.origin.y, screenVisibleFrame.maxY - newHeight)
        )
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    /// コンテンツが画面に収まるための初期スケール。1.0 を上限とする（拡大はしない）。
    /// 異常な size（0 以下）の場合は 1.0 を返してスケール変更しない。
    static func initialContentScale(contentSize: CGSize, screenVisibleSize: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0,
              screenVisibleSize.width > 0, screenVisibleSize.height > 0 else {
            return 1.0
        }
        let scaleX = screenVisibleSize.width / contentSize.width
        let scaleY = screenVisibleSize.height / contentSize.height
        return min(scaleX, scaleY, 1.0)
    }
}
