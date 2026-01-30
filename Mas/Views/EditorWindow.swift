import SwiftUI

struct EditorWindow: View {
    @StateObject private var viewModel: EditorViewModel
    @ObservedObject var screenshot: Screenshot
    @State private var copiedToClipboard = false
    @State private var showImage = true
    @State private var passThroughEnabled = false

    let onRecapture: ((CGRect) -> Void)?
    let onPassThroughChanged: ((Bool) -> Void)?

    init(screenshot: Screenshot, onRecapture: ((CGRect) -> Void)? = nil, onPassThroughChanged: ((Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(screenshot: screenshot))
        self.screenshot = screenshot
        self.onRecapture = onRecapture
        self.onPassThroughChanged = onPassThroughChanged
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
                if showImage {
                    if let region = screenshot.captureRegion {
                        Image(nsImage: screenshot.originalImage)
                            .resizable()
                            .frame(width: region.width, height: region.height)
                    } else {
                        Image(nsImage: screenshot.originalImage)
                    }
                }

                // 閉じるボタン（左上）
                Button(action: {
                    closeWindow()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(showImage ? .white : .gray)
                        .padding(6)
                        .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: 20, y: 20)

                // ボタン群（常に右上に固定）
                if screenshot.captureRegion != nil {
                    HStack(spacing: 4) {
                        // パススルートグル（画像非表示時のみ）
                        if !showImage {
                            Button(action: {
                                passThroughEnabled.toggle()
                                updatePassThrough()
                            }) {
                                Image(systemName: passThroughEnabled ? "hand.tap.fill" : "hand.tap")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(passThroughEnabled ? .blue : .gray)
                                    .padding(6)
                                    .background(Color.white.opacity(0.8))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        // 再キャプチャボタン
                        Button(action: {
                            let rect = getCurrentWindowRect()
                            onRecapture?(rect)
                            showImage = true
                            // 再キャプチャ時はパススルーをOFFに
                            if passThroughEnabled {
                                passThroughEnabled = false
                                updatePassThrough()
                            }
                        }) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(showImage ? .white : .gray)
                                .padding(6)
                                .background(showImage ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .position(x: geometry.size.width - (showImage ? 20 : 36), y: 20)
                }
            }
            .clipped()
        }
        .frame(minWidth: 50, minHeight: 50)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            showImage = false
        }
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

    private func updatePassThrough() {
        onPassThroughChanged?(passThroughEnabled)
    }

    private func closeWindow() {
        // floatingレベルのウィンドウ（エディタウィンドウ）を閉じる
        for window in NSApp.windows {
            if window.level == .floating && window.isVisible {
                window.close()
                return
            }
        }
    }
}
