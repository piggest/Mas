import SwiftUI
import AppKit

// ツールボックスの状態を管理するクラス（各ウィンドウごとにインスタンスを持つ）
class ToolboxState: ObservableObject {
    private let defaults = UserDefaults.standard
    private let toolKey = "selectedTool"
    private let colorKey = "selectedColor"
    private let lineWidthKey = "lineWidth"
    private let strokeEnabledKey = "strokeEnabled"

    @Published var selectedTool: EditTool = .arrow {
        didSet { defaults.set(selectedTool.rawValue, forKey: toolKey) }
    }
    @Published var selectedColor: Color = .red {
        didSet { saveColor(selectedColor) }
    }
    @Published var lineWidth: CGFloat = 5 {
        didSet { defaults.set(lineWidth, forKey: lineWidthKey) }
    }
    @Published var strokeEnabled: Bool = true {
        didSet { defaults.set(strokeEnabled, forKey: strokeEnabledKey) }
    }
    @Published var annotations: [any Annotation] = []
    @Published var selectedAnnotationIndex: Int? = nil

    var hasAnnotations: Bool {
        !annotations.isEmpty
    }

    var hasSelectedAnnotation: Bool {
        selectedAnnotationIndex != nil
    }

    init() {
        loadSettings()
    }

    private func loadSettings() {
        // ツール
        if let toolName = defaults.string(forKey: toolKey),
           let tool = EditTool(rawValue: toolName) {
            selectedTool = tool
        }

        // 色
        if let colorData = defaults.data(forKey: colorKey),
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            selectedColor = Color(nsColor)
        }

        // 線の太さ
        let savedWidth = defaults.double(forKey: lineWidthKey)
        if savedWidth > 0 {
            lineWidth = savedWidth
        }

        // 縁取り
        if defaults.object(forKey: strokeEnabledKey) != nil {
            strokeEnabled = defaults.bool(forKey: strokeEnabledKey)
        }
    }

    private func saveColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            defaults.set(data, forKey: colorKey)
        }
    }

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
            let tools = EditTool.allCases
            let firstRow = Array(tools.prefix(4))
            let secondRow = Array(tools.dropFirst(4))
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(firstRow, id: \.self) { tool in
                        toolButton(for: tool)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(secondRow, id: \.self) { tool in
                        toolButton(for: tool)
                    }
                }
            }
        }
    }

    private func toolButton(for tool: EditTool) -> some View {
        Button(action: { state.selectedTool = tool }) {
            VStack(spacing: 2) {
                Image(systemName: tool.icon)
                    .font(.system(size: 14, weight: .medium))
                Text(tool.rawValue)
                    .font(.system(size: 8))
            }
            .foregroundColor(state.selectedTool == tool ? .white : .primary)
            .frame(width: 42, height: 36)
            .background(state.selectedTool == tool ? Color.blue : Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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

