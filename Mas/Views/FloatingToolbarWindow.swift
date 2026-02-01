import SwiftUI
import AppKit

// フローティングツールバーの状態を保持するクラス（ToolboxStateとは独立）
class FloatingToolbarState: ObservableObject {
    @Published var selectedTool: EditTool = .arrow
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 5
    @Published var strokeEnabled: Bool = true
    @Published var hasAnnotations: Bool = false
    @Published var hasSelectedAnnotation: Bool = false

    // 元のToolboxStateから値をコピー
    func syncFrom(_ state: ToolboxState) {
        selectedTool = state.selectedTool
        selectedColor = state.selectedColor
        lineWidth = state.lineWidth
        strokeEnabled = state.strokeEnabled
        hasAnnotations = state.hasAnnotations
        hasSelectedAnnotation = state.hasSelectedAnnotation
    }

    // 元のToolboxStateに値を反映
    func syncTo(_ state: ToolboxState) {
        state.selectedTool = selectedTool
        state.selectedColor = selectedColor
        state.lineWidth = lineWidth
        state.strokeEnabled = strokeEnabled
    }
}

// フローティングツールバーウィンドウを管理するクラス
class FloatingToolbarWindowController {
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var hostingView: NSView?
    private var cachedToolbarSize: CGSize?

    // ツールバー独自の状態（EditorWindowのToolboxStateとは独立）
    private let toolbarState = FloatingToolbarState()
    private weak var originalState: ToolboxState?
    private var syncTimer: Timer?

    private var onDelete: (() -> Void)?
    private var onUndo: (() -> Void)?

    func show(attachedTo parent: NSWindow, state: ToolboxState, onUndo: @escaping () -> Void, onDelete: @escaping () -> Void = {}) {
        parentWindow = parent
        originalState = state
        self.onDelete = onDelete
        self.onUndo = onUndo

        // 元の状態から初期値をコピー
        toolbarState.syncFrom(state)

        if window == nil {
            createWindow()
        }

        updatePosition()
        window?.orderFront(nil)

        // 状態同期タイマーを開始（ツールバー→元の状態）
        startSyncTimer()

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
        stopSyncTimer()
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
    }

    func close() {
        hide()
        // window?.close()を呼ばず、参照をnilにするだけでARCに解放を任せる
        // contentView = nilも呼ばない
        window = nil
        hostingView = nil
        parentWindow = nil
        cachedToolbarSize = nil
        originalState = nil
    }

    // 元のToolboxStateの変更をツールバーに反映
    func updateFromState(_ state: ToolboxState) {
        toolbarState.syncFrom(state)
    }

    private func startSyncTimer() {
        // 定期的にツールバーの状態を元のToolboxStateに反映
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let state = self.originalState else { return }
            self.toolbarState.syncTo(state)
        }
    }

    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        // 注意: 最後の同期はSwiftUIの更新サイクル中に呼ばれる可能性があるため削除
        // タイマーは0.05秒ごとに動いているので、最後の同期は不要
    }

    private func createWindow() {
        let toolbarView = FloatingToolbarViewIndependent(
            state: toolbarState,
            onUndo: { [weak self] in self?.onUndo?() },
            onDelete: { [weak self] in self?.onDelete?() }
        )
        let hosting = NSHostingView(rootView: toolbarView)

        // ツールバーの本来のサイズを取得してキャッシュ
        let fittingSize = hosting.fittingSize
        let toolbarWidth = max(fittingSize.width, 400)
        let toolbarHeight = max(fittingSize.height, 50)
        cachedToolbarSize = CGSize(width: toolbarWidth, height: toolbarHeight)

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
        guard let parent = parentWindow, let toolbar = window else { return }

        let parentFrame = parent.frame

        // キャッシュされたサイズを使用（初回のみ計算）
        let toolbarSize = cachedToolbarSize ?? CGSize(width: 400, height: 50)
        let toolbarWidth = toolbarSize.width
        let toolbarHeight = toolbarSize.height

        // 親ウィンドウの下部中央に配置（はみ出しOK）
        let toolbarX = parentFrame.origin.x + (parentFrame.width - toolbarWidth) / 2
        let toolbarY = parentFrame.origin.y - toolbarHeight + 4

        toolbar.setFrame(
            NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight),
            display: false
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

// 独立した状態を使うツールグループボタン
struct ToolGroupButtonIndependent: View {
    @ObservedObject var state: FloatingToolbarState
    let group: ToolGroup
    @State private var showPopover = false

    private var currentTool: EditTool {
        group.tools.first(where: { $0 == state.selectedTool }) ?? group.tools[0]
    }

    private var isGroupSelected: Bool {
        group.tools.contains(state.selectedTool)
    }

    var body: some View {
        Button(action: {
            if isGroupSelected {
                showPopover = true
            } else {
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
            if !isGroupSelected {
                state.selectedTool = currentTool
            }
            showPopover = true
        }
    }
}

// 独立した状態を使う色選択ボタン
struct ColorPickerButtonIndependent: View {
    @ObservedObject var state: FloatingToolbarState
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

// 独立した状態を使うフローティングツールバービュー（ToolboxStateを参照しない）
struct FloatingToolbarViewIndependent: View {
    @ObservedObject var state: FloatingToolbarState
    let onUndo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            toolsSection
            Divider().frame(height: 24)
            optionsSection
            actionSection
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
        toolButton(for: .move)

        Divider().frame(height: 24)

        ToolGroupButtonIndependent(state: state, group: .drawing)
        ToolGroupButtonIndependent(state: state, group: .shapes)

        toolButton(for: .text)
        toolButton(for: .mosaic)
    }

    @ViewBuilder
    private var optionsSection: some View {
        ColorPickerButtonIndependent(state: state)

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
    private var actionSection: some View {
        if state.hasAnnotations || state.hasSelectedAnnotation {
            Divider().frame(height: 24)

            if state.hasSelectedAnnotation {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("削除 (Delete)")
            }

            if state.hasAnnotations {
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
