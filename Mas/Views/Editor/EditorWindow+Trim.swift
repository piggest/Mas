import AppKit
import AVFoundation
import SwiftUI

// MARK: - トリミング・領域コピー
//
// 編集モードでの「画像/動画のトリミング」「選択範囲のクリップボードコピー」
// および動画 → GIF エクスポート完了時の処理を集約する extension。
//
// - performCopyRegion       : 矩形選択範囲を切り出してクリップボードにコピー
// - performTrim             : 矩形選択範囲で画像 or 動画をトリミング
// - replaceWithTrimmedVideo : トリミング済み動画ファイルを現在の screenshot に差し替え
// - handleGifExportComplete : 動画 → GIF エクスポート完了時のフォローアップ

extension EditorWindow {

    func performCopyRegion(canvasRect: CGRect) {
        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let scale = imageSize.width / canvasSize.width

        // キャンバス座標→ピクセル座標に変換（左下原点→左上原点）
        let pixelX = canvasRect.origin.x * scale
        let pixelY = (canvasSize.height - canvasRect.origin.y - canvasRect.height) * scale
        let pixelWidth = canvasRect.width * scale
        let pixelHeight = canvasRect.height * scale

        let imageBounds = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
            .integral
            .intersection(imageBounds)

        guard cropRect.width > 0, cropRect.height > 0 else { return }

        guard let cgImage = screenshot.originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return }

        let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([croppedImage])
    }

    func performTrim(canvasRect: CGRect) {
        // 1. 既存アノテーションがあれば先に画像に焼き込み
        if !toolboxState.annotations.isEmpty {
            applyAnnotations()
        }

        let imageSize = screenshot.originalImage.size
        let canvasSize = screenshot.captureRegion?.size ?? imageSize
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let scale = imageSize.width / canvasSize.width

        // 2. キャンバス座標→ピクセル座標に変換
        // AnnotationCanvas は左下原点、CGImage は左上原点
        let pixelX = canvasRect.origin.x * scale
        let pixelY = (canvasSize.height - canvasRect.origin.y - canvasRect.height) * scale
        let pixelWidth = canvasRect.width * scale
        let pixelHeight = canvasRect.height * scale

        // 画像範囲内にclamp
        let imageBounds = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
            .integral
            .intersection(imageBounds)

        guard cropRect.width > 0, cropRect.height > 0 else { return }

        // 3. CGImage.cropping(to:) で切り取り
        guard let cgImage = screenshot.originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return }

        // 4. screenshot.updateImage() で画像更新
        screenshot.updateImage(croppedCGImage)

        // 5. captureRegion を新サイズに更新（トリミング後のキャンバスサイズ）
        let newCanvasWidth = cropRect.width / scale
        let newCanvasHeight = cropRect.height / scale
        let oldRegion = screenshot.captureRegion ?? CGRect(origin: .zero, size: imageSize)
        screenshot.captureRegion = CGRect(
            x: oldRegion.origin.x,
            y: oldRegion.origin.y,
            width: newCanvasWidth,
            height: newCanvasHeight
        )

        // 6. ウィンドウをトリミング範囲のスクリーン位置に移動＆リサイズ
        // canvasRect.originはキャンバス座標（左下原点）でのトリミング範囲の左下
        // originDelta: SwiftUIの.offset()によるキャンバスのシフト量
        let dx = resizeState.originDelta.x
        let dy = resizeState.originDelta.y
        if let window = parentWindow {
            let oldFrame = window.frame
            // キャンバスの左下のスクリーン座標 = ウィンドウ上端 - dy - canvasHeight
            // トリミング範囲の左下のスクリーン座標:
            let screenX = oldFrame.origin.x + dx + canvasRect.origin.x
            let screenY = oldFrame.origin.y + oldFrame.height - dy - canvasSize.height + canvasRect.origin.y
            let newFrame = NSRect(
                x: screenX,
                y: screenY,
                width: newCanvasWidth,
                height: newCanvasHeight
            )
            window.setFrame(newFrame, display: true)
        }
        resizeState.reset()

        // 7. 自動保存・クリップボードコピー（設定に応じて）
        let newImage = screenshot.originalImage
        let autoSaveEnabled = UserDefaults.standard.object(forKey: "autoSaveEnabled") as? Bool ?? true
        if autoSaveEnabled {
            saveEditedImage(newImage)
        }
        let autoCopyToClipboard = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([newImage])
        }

        // ドラッグ用画像をクリア
        imageForDrag = nil

        // 8. ツールを .move に戻す
        toolboxState.selectedTool = .move
        toolbarController?.setTool(.move)
    }

    func replaceWithTrimmedVideo(url: URL) {
        // ツールバーを閉じる
        videoToolbarController?.close()
        videoToolbarController = nil
        videoPlayerState?.pause()
        videoPlayerState = nil

        // サムネイル生成
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            screenshot.originalImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        screenshot.savedURL = url

        // 履歴に追加
        NotificationCenter.default.post(name: .addFileToHistory, object: url)

        // 新しいプレーヤーを初期化
        if let player = VideoPlayerState(url: url) {
            videoPlayerState = player
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let parent = self.parentWindow {
                    let controller = VideoPlayerToolbarController()
                    controller.show(attachedTo: parent, playerState: player, onTrimComplete: { [self] trimmedURL in
                        self.replaceWithTrimmedVideo(url: trimmedURL)
                    }, onGifExportComplete: { [self] gifURL in
                        self.handleGifExportComplete(url: gifURL)
                    })
                    self.videoToolbarController = controller
                }
                player.play()
            }
        }
    }

    func handleGifExportComplete(url: URL) {
        // 履歴に追加
        NotificationCenter.default.post(name: .addFileToHistory, object: url)
        // Finderで表示
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
