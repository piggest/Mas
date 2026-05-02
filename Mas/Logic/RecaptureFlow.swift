import AppKit
import CoreGraphics

/// recapture の純粋フロー部分（DI 可能・テスト可能）。
/// AppKit の `NSWindow` 状態更新（orderOut/makeKeyAndOrderFront）や `Screenshot` 状態更新は
/// 呼び出し側に残し、ここでは「画面キャプチャ → crop → 結果」のみを扱う。
struct RecaptureFlow {

    let capturer: ScreenCapturing
    let sleeper: SleepProviding
    /// 開発モード判定。true のときのみ事前 hide + sleep を実行する。
    let isDevMode: Bool

    /// 開発モード時の事前 sleep 時間（ns）。
    static let devModeSleepNanoseconds: UInt64 = 200_000_000

    /// recapture 処理の結果。
    struct Result {
        /// 切り出された CGImage。
        let croppedImage: CGImage
        /// 実際に使った region。
        let region: CGRect
    }

    /// 指定された region で recapture を実行する。
    /// - Parameters:
    ///   - region: CG 座標系のキャプチャ範囲（呼び出し側で `window.frame` から計算）
    ///   - screen: region が属するスクリーン
    ///   - hideWindow: 開発モード時に呼ばれる、ウィンドウを隠すコールバック
    /// - Returns: 成功時は Result、画像範囲外などで切り出せない場合は nil
    func run(
        region: CGRect,
        screen: NSScreen,
        hideWindow: @MainActor () -> Void
    ) async throws -> Result? {

        // 開発モード時のみ事前に隠して待つ（通常モードは sharingType=.none で自身が映らない）
        if isDevMode {
            await MainActor.run { hideWindow() }
            await sleeper.sleep(nanoseconds: Self.devModeSleepNanoseconds)
        }

        let fullScreenImage = try await capturer.captureScreen(screen)

        let imageWidth = CGFloat(fullScreenImage.width)
        let imageHeight = CGFloat(fullScreenImage.height)
        let scale = CropMath.imageScale(imageWidth: imageWidth, screenWidth: screen.frame.width)

        // CGグローバル座標をスクリーン相対座標に変換
        let scaledRect = CropMath.scaledRect(region: region, screenCGFrame: screen.cgFrame, scale: scale)
        let clampedRect = CropMath.clampedRect(scaledRect, imageSize: CGSize(width: imageWidth, height: imageHeight))

        guard !clampedRect.isEmpty, let croppedImage = fullScreenImage.cropping(to: clampedRect) else {
            return nil
        }

        return Result(croppedImage: croppedImage, region: region)
    }
}
