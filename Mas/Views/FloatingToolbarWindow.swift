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

    // 各ツールグループ内で最後に選択されたツールを記憶
    var lastDrawingTool: EditTool = .pen
    var lastShapeTool: EditTool = .arrow

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

    // ツール選択時に最後の選択を記憶
    func selectTool(_ tool: EditTool) {
        selectedTool = tool
        if let group = ToolGroup.groupFor(tool) {
            switch group {
            case .drawing:
                lastDrawingTool = tool
            case .shapes:
                lastShapeTool = tool
            }
        }
    }

    // グループ内で最後に選択されたツールを取得
    func lastToolFor(group: ToolGroup) -> EditTool {
        switch group {
        case .drawing:
            return lastDrawingTool
        case .shapes:
            return lastShapeTool
        }
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

        // 親ウィンドウの子ウィンドウとして追加（常に親より前面に表示）
        if let toolbarWindow = window {
            parent.addChildWindow(toolbarWindow, ordered: .above)
        }

        // 出現アニメーション
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        }

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
        // 親ウィンドウから子ウィンドウを削除
        if let toolbarWindow = window, let parent = parentWindow {
            parent.removeChildWindow(toolbarWindow)
        }

        // 消えるアニメーション
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window?.alphaValue = 1  // リセット
        })
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

    private var isSyncPaused = false

    func pauseSync() {
        isSyncPaused = true
    }

    func resumeSync() {
        isSyncPaused = false
    }

    private func startSyncTimer() {
        // 定期的にツールバー → ToolboxState の一方向同期（即座に反映するため短い間隔）
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, let state = self.originalState else { return }
            // 同期が一時停止中は何もしない
            if self.isSyncPaused { return }
            // hasAnnotations, hasSelectedAnnotationはToolboxStateから読み取り
            if self.toolbarState.hasAnnotations != state.hasAnnotations {
                self.toolbarState.hasAnnotations = state.hasAnnotations
            }
            if self.toolbarState.hasSelectedAnnotation != state.hasSelectedAnnotation {
                self.toolbarState.hasSelectedAnnotation = state.hasSelectedAnnotation
            }

            // lineWidthが変わったら直接アノテーションを更新（ドラッグ中の即時反映）
            if self.toolbarState.lineWidth != state.lineWidth {
                state.lineWidth = self.toolbarState.lineWidth
                // 選択中のアノテーションの線幅を更新
                if state.selectedTool == .move,
                   let index = state.selectedAnnotationIndex,
                   index < state.annotations.count {
                    state.annotations[index].annotationLineWidth = self.toolbarState.lineWidth
                    state.objectWillChange.send()
                }
            }

            // ツールバー → ToolboxState（lineWidth以外）
            state.selectedTool = self.toolbarState.selectedTool
            state.selectedColor = self.toolbarState.selectedColor
            state.strokeEnabled = self.toolbarState.strokeEnabled
        }
    }

    // 選択変更時にToolboxStateの属性をツールバーに反映（明示的に呼び出す）
    func syncAttributesFromState() {
        guard let state = originalState else { return }
        toolbarState.selectedColor = state.selectedColor
        toolbarState.lineWidth = state.lineWidth
        toolbarState.strokeEnabled = state.strokeEnabled
    }

    // ツールを変更
    func setTool(_ tool: EditTool) {
        toolbarState.selectedTool = tool
        originalState?.selectedTool = tool
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
            onDelete: { [weak self] in self?.onDelete?() },
            onLineWidthChanged: { [weak self] newValue in
                self?.originalState?.lineWidth = newValue
            }
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

        // 親ウィンドウの下部左寄せに配置
        var toolbarX = parentFrame.origin.x
        var toolbarY = parentFrame.origin.y - toolbarHeight + 4

        // 画面内に収まるように調整
        if let screen = parent.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            // 左端チェック
            if toolbarX < screenFrame.minX {
                toolbarX = screenFrame.minX
            }
            // 右端チェック
            if toolbarX + toolbarWidth > screenFrame.maxX {
                toolbarX = screenFrame.maxX - toolbarWidth
            }
            // 下端チェック（画面下にはみ出す場合は親ウィンドウの上に配置）
            if toolbarY < screenFrame.minY {
                toolbarY = parentFrame.maxY - 4
            }
            // 上端チェック
            if toolbarY + toolbarHeight > screenFrame.maxY {
                toolbarY = screenFrame.maxY - toolbarHeight
            }
        }

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
        // グループ内で最後に選択されたツールを使用
        state.lastToolFor(group: group)
    }

    private var isGroupSelected: Bool {
        group.tools.contains(state.selectedTool)
    }

    var body: some View {
        Button(action: {
            if isGroupSelected {
                showPopover = true
            } else {
                state.selectTool(currentTool)
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
        .buttonStyle(NoHighlightButtonStyle())
        .help(currentTool.rawValue)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                ForEach(group.tools, id: \.self) { tool in
                    Button(action: {
                        state.selectTool(tool)
                        showPopover = false
                    }) {
                        HStack {
                            Image(systemName: tool.icon)
                                .font(.system(size: 12))
                            Text(tool.rawValue)
                                .font(.system(size: 12))
                            Spacer()
                            if state.lastToolFor(group: group) == tool {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minWidth: 100)
                        .background(state.lastToolFor(group: group) == tool ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                }
            }
            .padding(8)
        }
        .onTapGesture(count: 1) {
            if !isGroupSelected {
                state.selectTool(currentTool)
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
        .buttonStyle(NoHighlightButtonStyle())
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
                                .buttonStyle(NoHighlightButtonStyle())
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
    var onLineWidthChanged: ((CGFloat) -> Void)?

    private let buttonSize: CGFloat = 28
    private let iconSize: CGFloat = 12

    @State private var appeared = false
    @State private var backgroundAppeared = false

    var body: some View {
        HStack(spacing: 6) {
            toolsSection
            optionsSection
            actionSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .opacity(backgroundAppeared ? 1 : 0)
        )
        .overlay(
            Capsule()
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                .opacity(backgroundAppeared ? 1 : 0)
        )
        .fixedSize()
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                appeared = true
            }
            // ボタンと同時に背景をフェードイン
            withAnimation(.easeIn(duration: 0.2)) {
                backgroundAppeared = true
            }
        }
    }

    private func animatedOffset(index: Int) -> CGFloat {
        return appeared ? 0 : -CGFloat(index + 1) * 40
    }

    private func animatedOpacity(index: Int) -> Double {
        1
    }

    private func animationDelay(index: Int) -> Double {
        0
    }

    @ViewBuilder
    private var toolsSection: some View {
        circleToolButton(for: .move, index: 0)

        ToolGroupButtonCircle(state: state, group: .drawing, buttonSize: buttonSize, iconSize: iconSize)
            .offset(x: animatedOffset(index: 1))
            .animation(.easeOut(duration: 0.2), value: appeared)

        ToolGroupButtonCircle(state: state, group: .shapes, buttonSize: buttonSize, iconSize: iconSize)
            .offset(x: animatedOffset(index: 2))
            .animation(.easeOut(duration: 0.2), value: appeared)

        circleToolButton(for: .text, index: 3)
        circleToolButton(for: .mosaic, index: 4)
    }

    @ViewBuilder
    private var optionsSection: some View {
        // 区切り
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 4, height: 4)
            .padding(.horizontal, 4)

        ColorPickerButtonCircle(state: state, buttonSize: buttonSize)
            .offset(x: animatedOffset(index: 6))
            .animation(.easeOut(duration: 0.2), value: appeared)

        // 線の太さ
        HStack(spacing: 2) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
            Slider(value: $state.lineWidth, in: 1...10, step: 1)
                .frame(width: 60)
                .tint(.blue)
                .onChange(of: state.lineWidth) { newValue in
                    onLineWidthChanged?(newValue)
                }
            Circle()
                .fill(Color.secondary)
                .frame(width: 10, height: 10)
        }
        .offset(x: animatedOffset(index: 7))
        .animation(.easeOut(duration: 0.2), value: appeared)

        // 縁取りボタン
        Button(action: { state.strokeEnabled.toggle() }) {
            Image(systemName: state.strokeEnabled ? "diamond.inset.filled" : "diamond")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(state.strokeEnabled ? .white : .secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(state.strokeEnabled ? Color.blue : Color.white.opacity(0.9))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .help("縁取り")
        .offset(x: animatedOffset(index: 8))
        .animation(.easeOut(duration: 0.2), value: appeared)
    }

    @ViewBuilder
    private var actionSection: some View {
        if state.hasAnnotations || state.hasSelectedAnnotation {
            // 区切り
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 4, height: 4)
                .padding(.horizontal, 4)

            if state.hasSelectedAnnotation {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: iconSize))
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.pink)
                        .clipShape(Circle())
                }
                .buttonStyle(NoHighlightButtonStyle())
                .help("削除 (Delete)")
            }

            if state.hasAnnotations {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: iconSize))
                        .foregroundColor(.primary)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(NoHighlightButtonStyle())
                .help("取消")
            }
        }
    }

    private func circleToolButton(for tool: EditTool, index: Int) -> some View {
        Button(action: { state.selectedTool = tool }) {
            Image(systemName: tool.icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(state.selectedTool == tool ? .white : .secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(state.selectedTool == tool ? Color.blue : Color.white.opacity(0.9))
                .clipShape(Circle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .help(tool.rawValue)
        .offset(x: animatedOffset(index: index))
        .animation(.easeOut(duration: 0.2), value: appeared)
    }
}

// 丸いツールグループボタン
struct ToolGroupButtonCircle: View {
    @ObservedObject var state: FloatingToolbarState
    let group: ToolGroup
    let buttonSize: CGFloat
    let iconSize: CGFloat
    @State private var showPopover = false

    private var currentTool: EditTool {
        state.lastToolFor(group: group)
    }

    private var isGroupSelected: Bool {
        group.tools.contains(state.selectedTool)
    }

    var body: some View {
        Button(action: {
            if isGroupSelected {
                showPopover = true
            } else {
                state.selectTool(currentTool)
            }
        }) {
            HStack(spacing: 2) {
                Image(systemName: currentTool.icon)
                    .font(.system(size: iconSize, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(isGroupSelected ? .white : .secondary)
            .frame(width: buttonSize + 10, height: buttonSize)
            .background(isGroupSelected ? Color.blue : Color.white.opacity(0.9))
            .clipShape(Capsule())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .help(currentTool.rawValue)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                ForEach(group.tools, id: \.self) { tool in
                    Button(action: {
                        state.selectTool(tool)
                        showPopover = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 12))
                                .frame(width: 20)
                            Text(tool.rawValue)
                                .font(.system(size: 12))
                            Spacer()
                            if state.lastToolFor(group: group) == tool {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 100)
                        .background(state.lastToolFor(group: group) == tool ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                }
            }
            .padding(8)
        }
        .onTapGesture(count: 1) {
            if !isGroupSelected {
                state.selectTool(currentTool)
            }
            showPopover = true
        }
    }
}

// 丸い色選択ボタン
struct ColorPickerButtonCircle: View {
    @ObservedObject var state: FloatingToolbarState
    let buttonSize: CGFloat
    @State private var showPopover = false

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .black, .white, .gray]

    var body: some View {
        Button(action: { showPopover = true }) {
            Circle()
                .fill(state.selectedColor)
                .frame(width: buttonSize - 8, height: buttonSize - 8)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .help("色選択")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                ForEach(0..<2) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<5) { col in
                            let index = row * 5 + col
                            if index < colors.count {
                                Button(action: {
                                    state.selectedColor = colors[index]
                                    showPopover = false
                                }) {
                                    Circle()
                                        .fill(colors[index])
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(state.selectedColor == colors[index] ? Color.blue : Color.gray.opacity(0.3), lineWidth: state.selectedColor == colors[index] ? 3 : 1)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                }
                                .buttonStyle(NoHighlightButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}
