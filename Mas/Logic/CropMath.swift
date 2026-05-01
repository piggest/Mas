import CoreGraphics

/// 画面キャプチャした全画面画像から region を切り出すための純粋計算。
enum CropMath {

    /// 物理ピクセル / 論理ポイントのスケール係数。
    static func imageScale(imageWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        guard screenWidth > 0 else { return 1.0 }
        return imageWidth / screenWidth
    }

    /// CG グローバル座標の region を、特定スクリーン画像内のピクセル座標に変換する。
    static func scaledRect(region: CGRect, screenCGFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (region.origin.x - screenCGFrame.origin.x) * scale,
            y: (region.origin.y - screenCGFrame.origin.y) * scale,
            width: region.width * scale,
            height: region.height * scale
        )
    }

    /// 画像範囲にクランプする（食み出し部分をカット）。
    static func clampedRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        rect.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
