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

// ツールグループの定義
enum ToolGroup {
    case drawing  // pen, highlight
    case shapes   // arrow, rectangle, ellipse

    var tools: [EditTool] {
        switch self {
        case .drawing: return [.pen, .highlight]
        case .shapes: return [.arrow, .rectangle, .ellipse]
        }
    }

    static func groupFor(_ tool: EditTool) -> ToolGroup? {
        if ToolGroup.drawing.tools.contains(tool) { return .drawing }
        if ToolGroup.shapes.tools.contains(tool) { return .shapes }
        return nil
    }
}

// コンボボックス風のツール選択ボタン
struct ToolGroupButton: View {
    @ObservedObject var state: ToolboxState
    let group: ToolGroup
    @State private var showPopover = false

    private var currentTool: EditTool {
        // グループ内で選択されているツールがあればそれを、なければ最初のツールを表示
        group.tools.first(where: { $0 == state.selectedTool }) ?? group.tools[0]
    }

    private var isGroupSelected: Bool {
        group.tools.contains(state.selectedTool)
    }

    var body: some View {
        Button(action: {
            if isGroupSelected {
                // 既にグループ内のツールが選択されていたらポップオーバーを開く
                showPopover = true
            } else {
                // そうでなければ現在のツールを選択
                state.selectedTool = currentTool
            }
        }) {
            HStack(spacing: 2) {
                Image(systemName: currentTool.icon)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(isGroupSelected ? .white : .primary)
            .frame(width: 40, height: 28)
            .background(isGroupSelected ? Color.blue : Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(currentTool.rawValue)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                ForEach(group.tools, id: \.self) { tool in
                    Button(action: {
                        state.selectedTool = tool
                        showPopover = false
                    }) {
                        HStack {
                            Image(systemName: tool.icon)
                                .font(.system(size: 12))
                            Text(tool.rawValue)
                                .font(.system(size: 12))
                            Spacer()
                            if state.selectedTool == tool {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minWidth: 100)
                        .background(state.selectedTool == tool ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .onTapGesture(count: 1) {
            // シングルクリックでツール選択 + ポップオーバー
            if !isGroupSelected {
                state.selectedTool = currentTool
            }
            showPopover = true
        }
    }
}

// 色選択のコンボボックス風ボタン
struct ColorPickerButton: View {
    @ObservedObject var state: ToolboxState
    @State private var showPopover = false

    private let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink, .black, .white, .gray]

    var body: some View {
        Button(action: { showPopover = true }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(state.selectedColor)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(width: 40, height: 28)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("色選択")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                // 2行5列のグリッド
                ForEach(0..<2) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<5) { col in
                            let index = row * 5 + col
                            if index < colors.count {
                                Button(action: {
                                    state.selectedColor = colors[index]
                                    showPopover = false
                                }) {
                                    Circle()
                                        .fill(colors[index])
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Circle()
                                                .stroke(state.selectedColor == colors[index] ? Color.blue : Color.gray.opacity(0.3), lineWidth: state.selectedColor == colors[index] ? 2 : 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

// フローティングツールバーのビュー
struct FloatingToolbarView: View {
    @ObservedObject var state: ToolboxState
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            toolsSection
            Divider().frame(height: 24)
            optionsSection
            undoSection
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

    @ViewBuilder
    private var toolsSection: some View {
        // 移動ツール
        toolButton(for: .move)

        Divider().frame(height: 24)

        // 描画ツールグループ（ペン、マーカー）
        ToolGroupButton(state: state, group: .drawing)

        // 形状ツールグループ（矢印、四角、丸）
        ToolGroupButton(state: state, group: .shapes)

        // テキストツール
        toolButton(for: .text)

        // モザイクツール
        toolButton(for: .mosaic)
    }

    @ViewBuilder
    private var optionsSection: some View {
        // 色選択
        ColorPickerButton(state: state)

        // サイズスライダー
        HStack(spacing: 4) {
            Image(systemName: "line.diagonal")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Slider(value: $state.lineWidth, in: 1...10, step: 1)
                .frame(width: 50)
            Image(systemName: "line.diagonal")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }

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
    }

    @ViewBuilder
    private var undoSection: some View {
        if state.hasAnnotations {
            Divider().frame(height: 24)

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

    private func toolButton(for tool: EditTool) -> some View {
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
