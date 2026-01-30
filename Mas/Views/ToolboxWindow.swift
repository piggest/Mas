import SwiftUI
import AppKit

// ツールボックスの状態を共有するためのObservableObject
class ToolboxState: ObservableObject {
    static let shared = ToolboxState()

    @Published var selectedTool: EditTool = .arrow
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 3
    @Published var annotations: [any Annotation] = []

    private init() {}

    func reset() {
        selectedTool = .arrow
        selectedColor = .red
        lineWidth = 3
        annotations = []
    }
}

// ツールボックスウィンドウのコンテンツ
struct ToolboxContentView: View {
    @ObservedObject var state: ToolboxState
    let onUndo: () -> Void

    private let colors: [Color] = [.red, .blue, .green, .yellow, .black, .white]

    var body: some View {
        VStack(spacing: 12) {
            toolSelection
            Divider()
            colorSelection
            Divider()
            sizeSlider
            if !state.annotations.isEmpty {
                Divider()
                undoButton
            }
        }
        .padding(12)
        .frame(width: 180)
    }

    private var toolSelection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ツール")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(EditTool.allCases, id: \.self) { tool in
                    Button(action: { state.selectedTool = tool }) {
                        VStack(spacing: 2) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 16, weight: .medium))
                            Text(tool.rawValue)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(state.selectedTool == tool ? .white : .primary)
                        .frame(width: 36, height: 40)
                        .background(state.selectedTool == tool ? Color.blue : Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorSelection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("色")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(colors, id: \.self) { color in
                    Button(action: { state.selectedColor = color }) {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(state.selectedColor == color ? Color.blue : Color.gray.opacity(0.3), lineWidth: state.selectedColor == color ? 3 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sizeSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("サイズ: \(Int(state.lineWidth))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Slider(value: $state.lineWidth, in: 1...10, step: 1)
                Image(systemName: "line.diagonal")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
                Text("取消")
                    .font(.system(size: 12))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// ツールボックスウィンドウを管理するクラス
class ToolboxWindowController {
    static let shared = ToolboxWindowController()

    private var window: NSWindow?
    private var onUndo: (() -> Void)?

    private init() {}

    func show(near editorFrame: CGRect, onUndo: @escaping () -> Void) {
        self.onUndo = onUndo

        if window == nil {
            createWindow()
        }

        // エディタウィンドウの左側に配置
        let toolboxX = editorFrame.origin.x - 200
        let toolboxY = editorFrame.origin.y + editorFrame.height - 300

        window?.setFrameOrigin(NSPoint(x: max(10, toolboxX), y: max(10, toolboxY)))
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func createWindow() {
        let contentView = ToolboxContentView(state: ToolboxState.shared) { [weak self] in
            self?.onUndo?()
        }

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 280),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.title = "ツール"
        window.contentViewController = hostingController
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false

        self.window = window
    }

    func updateAnnotations(_ annotations: [any Annotation]) {
        ToolboxState.shared.annotations = annotations
    }
}
