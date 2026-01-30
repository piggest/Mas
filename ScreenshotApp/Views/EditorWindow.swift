import SwiftUI

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @State private var copiedToClipboard = false

    let onRecapture: ((CGRect) -> Void)?

    init(screenshot: Screenshot, onRecapture: ((CGRect) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.onRecapture = onRecapture
    }

    private func getCurrentWindowRect() -> CGRect {
        // すべてのウィンドウからMasのウィンドウを探す
        for window in NSApp.windows {
            // floating levelのウィンドウを探す
            if window.level == .floating && window.isVisible {
                let frame = window.frame
                let screenHeight = NSScreen.main?.frame.height ?? 0
                // 左下原点から左上原点に変換
                let rect = CGRect(
                    x: frame.origin.x,
                    y: screenHeight - frame.origin.y - frame.height,
                    width: frame.width,
                    height: frame.height
                )
                return rect
            }
        }
        return screenshot.captureRegion ?? .zero
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 画像を選択範囲と同じサイズで表示（拡縮しない）
                if let region = screenshot.captureRegion {
                    Image(nsImage: screenshot.originalImage)
                        .resizable()
                        .frame(width: region.width, height: region.height)
                } else {
                    Image(nsImage: screenshot.originalImage)
                }

                // 再キャプチャボタン（常に右上に固定）
                if screenshot.mode == .region && screenshot.captureRegion != nil {
                    Button(action: {
                        let rect = getCurrentWindowRect()
                        onRecapture?(rect)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: geometry.size.width - 20, y: 20)
                }
            }
            .clipped()
        }
        .frame(minWidth: 50, minHeight: 50)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .border(Color.gray.opacity(0.5), width: 1)
        .contextMenu {
            Button("閉じる") {
                closeWindow()
            }
            Divider()
            Button("クリップボードにコピー") {
                copyToClipboard()
            }
        }
    }

    private func copyToClipboard() {
        if viewModel.copyToClipboard() {
            copiedToClipboard = true
        }
    }

    private func closeWindow() {
        // borderlessウィンドウを閉じる
        for window in NSApp.windows {
            if window.contentViewController?.view.window == window && window.styleMask.contains(.borderless) {
                window.close()
                return
            }
        }
        // フォールバック
        NSApp.mainWindow?.close()
    }
}
