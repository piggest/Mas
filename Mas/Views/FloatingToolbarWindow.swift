import SwiftUI
import AppKit

// フローティングツールバーウィンドウを管理するクラス
class FloatingToolbarWindowController {
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var hostingView: NSView?

    func show(attachedTo parent: NSWindow, state: ToolboxState, onUndo: @escaping () -> Void) {
        parentWindow = parent

        if window == nil {
            createWindow(state: state, onUndo: onUndo)
        }

        updatePosition()
        window?.orderFront(nil)

        // 親ウィンドウの移動・リサイズを監視
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    func hide() {
        window?.orderOut(nil)
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
    }

    func close() {
        hide()
        // window?.close()は呼ばない（アプリ終了を防ぐ）
        window = nil
        hostingView = nil
        parentWindow = nil
    }

    private func createWindow(state: ToolboxState, onUndo: @escaping () -> Void) {
        let toolbarView = FloatingToolbarView(state: state, onUndo: onUndo)
        let hosting = NSHostingView(rootView: toolbarView)

        // ツールバーの本来のサイズを取得
        let fittingSize = hosting.fittingSize
        let toolbarWidth = fittingSize.width
        let toolbarHeight = fittingSize.height

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        hosting.frame = NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight)
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        self.window = window
        self.hostingView = hosting
    }

    private func updatePosition() {
        guard let parent = parentWindow, let toolbar = window, let hosting = hostingView as? NSHostingView<FloatingToolbarView> else { return }

        let parentFrame = parent.frame

        // ツールバーの本来のサイズを取得
        let fittingSize = hosting.fittingSize
        let toolbarWidth = fittingSize.width
        let toolbarHeight = fittingSize.height

        // 親ウィンドウの下部中央に配置（はみ出しOK）
        let toolbarX = parentFrame.origin.x + (parentFrame.width - toolbarWidth) / 2
        let toolbarY = parentFrame.origin.y - toolbarHeight + 4

        toolbar.setFrame(
            NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight),
            display: true
        )
    }
}

// フローティングツールバーのビュー
struct FloatingToolbarView: View {
    @ObservedObject var state: ToolboxState
    let onUndo: () -> Void

    private let colors: [Color] = [.red, .blue, .green, .yellow, .black, .white]

    var body: some View {
        HStack(spacing: 12) {
            // ツール選択
            HStack(spacing: 4) {
                ForEach(EditTool.allCases, id: \.self) { tool in
                    Button(action: { state.selectedTool = tool }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(state.selectedTool == tool ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(state.selectedTool == tool ? Color.blue : Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(tool.rawValue)
                }
            }

            Divider()
                .frame(height: 24)

            // 色選択
            HStack(spacing: 4) {
                ForEach(colors, id: \.self) { color in
                    Button(action: { state.selectedColor = color }) {
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(state.selectedColor == color ? Color.blue : Color.gray.opacity(0.3), lineWidth: state.selectedColor == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .frame(height: 24)

            // サイズスライダー
            HStack(spacing: 4) {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Slider(value: $state.lineWidth, in: 1...10, step: 1)
                    .frame(width: 60)
                Image(systemName: "line.diagonal")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 24)

            // 縁取りトグル
            Button(action: { state.strokeEnabled.toggle() }) {
                Image(systemName: state.strokeEnabled ? "square.dashed" : "square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(state.strokeEnabled ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(state.strokeEnabled ? Color.blue : Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("縁取り")

            // 取消ボタン
            if !state.annotations.isEmpty {
                Divider()
                    .frame(height: 24)

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("取消")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .fixedSize()
    }
}
