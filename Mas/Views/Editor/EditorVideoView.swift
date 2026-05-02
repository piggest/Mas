import AVFoundation
import SwiftUI

// MARK: - 動画再生用 NSView (AVPlayerLayer ベース)

/// AVPlayer を直接 layer で表示する NSView。コントロールは表示しない。
/// エディタが動画モードのとき `VideoPlayerView` 経由で SwiftUI に組み込まれる。
class VideoLayerView: NSView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // playerLayer のリサイズ時にデフォルトの暗黙アニメーションが入ると
        // フレームが揺れるため、CATransaction でアニメーションを無効化する
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - SwiftUI から VideoLayerView を組み込む Representable

/// SwiftUI の View ヒエラルキーに `VideoLayerView` を埋め込むためのラッパ。
/// `player` インスタンスが入れ替わると `playerLayer.player` も追従する。
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoLayerView {
        VideoLayerView(player: player)
    }

    func updateNSView(_ nsView: VideoLayerView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}

// MARK: - GIF フレーム表示用 View

/// GIF アニメーション再生用の SwiftUI View。
/// `GifPlayerState` が `@Published` で現在フレームを公開しており、変更時に再描画される。
struct GifFrameView: View {
    @ObservedObject var playerState: GifPlayerState
    /// 表示領域。nil の場合は画像の自然サイズで描画する。
    var region: CGRect?

    var body: some View {
        if let region = region {
            Image(nsImage: playerState.currentFrameImage)
                .resizable()
                .frame(width: region.width, height: region.height)
        } else {
            Image(nsImage: playerState.currentFrameImage)
        }
    }
}
