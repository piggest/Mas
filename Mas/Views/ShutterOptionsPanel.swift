import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - VisualEffectBlur Helper

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Shutter Mode Tab

enum ShutterTab: String, CaseIterable {
    case delayed = "時限"
    case interval = "インターバル"
    case changeDetection = "変化検知"
    case programmable = "プログラム"

    var icon: String {
        switch self {
        case .delayed: return "timer"
        case .interval: return "arrow.triangle.2.circlepath"
        case .changeDetection: return "eye"
        case .programmable: return "list.bullet.rectangle"
        }
    }
}

// MARK: - SwiftUI View

struct ShutterOptionsView: View {
    @ObservedObject var shutterService: ShutterService
    let onStartDelayed: (Int) -> Void
    let onStartInterval: (Double, Int) -> Void
    let onStartChangeDetection: () -> Void
    let onStartProgrammable: ([ProgramStep]) -> Void
    let onStop: () -> Void
    var onClose: (() -> Void)?
    var onSelectMonitorRegion: (() -> Void)?
    var onResetMonitorRegion: (() -> Void)?
    var onSelectStepMonitorRegion: ((_ completion: @escaping (CGRect?) -> Void) -> Void)?
    var onSizeChange: ((CGSize) -> Void)?
    let initialMode: ShutterTab

    @State private var selectedDelay: Double = 3
    @State private var selectedInterval: Double = 5
    @State private var maxCaptureCount: Double = 0
    @State private var programSteps: [ProgramStep] = ProgramStepStore.loadLastSteps()
    @State private var draggingStepId: UUID?
    @State private var showSavePopover = false
    @State private var saveName = ""
    @State private var savedPrograms: [String: [ProgramStep]] = ProgramStepStore.loadAllPrograms()

    private static let compactWidth: CGFloat = 44

    private var panelWidth: CGFloat {
        switch initialMode {
        case .delayed, .interval, .changeDetection: return Self.compactWidth
        case .programmable: return 300
        }
    }

    static func panelSize(for mode: ShutterTab) -> CGSize {
        switch mode {
        case .delayed:         return CGSize(width: compactWidth, height: 140)
        case .interval:        return CGSize(width: compactWidth, height: 190)
        case .changeDetection: return CGSize(width: compactWidth, height: 260)
        case .programmable:    return CGSize(width: 300, height: 130)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if initialMode == .programmable {
                // プログラマブルはワイドレイアウト
                HStack(spacing: 5) {
                    Image(systemName: initialMode.icon)
                        .font(.system(size: 10))
                        .foregroundColor(isActiveMode(initialMode) ? .cyan : .white.opacity(0.8))
                    Text(initialMode.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()

                    // 保存ボタン
                    Button(action: {
                        saveName = ""
                        showSavePopover = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundColor(programSteps.isEmpty ? .white.opacity(0.2) : .white.opacity(0.6))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                    .disabled(programSteps.isEmpty)
                    .popover(isPresented: $showSavePopover) {
                        savePopoverContent
                    }

                    // 読み込みメニュー
                    Menu {
                        if savedPrograms.isEmpty {
                            Text("保存済みプログラムなし")
                        } else {
                            ForEach(savedPrograms.keys.sorted(), id: \.self) { name in
                                Button(name) {
                                    if let steps = savedPrograms[name] {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            programSteps = steps.map { step in
                                                var s = step
                                                s.id = UUID()
                                                s.children = assignNewIds(step.children)
                                                return s
                                            }
                                        }
                                        autoSave()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            onSizeChange?(CGSize(width: 300, height: programmableHeight()))
                                        }
                                    }
                                }
                            }
                            Divider()
                            Menu("削除") {
                                ForEach(savedPrograms.keys.sorted(), id: \.self) { name in
                                    Button(name, role: .destructive) {
                                        ProgramStepStore.deleteProgram(name: name)
                                        savedPrograms = ProgramStepStore.loadAllPrograms()
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)

                    Button(action: { onClose?() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 8)

                programmableContent
            } else {
                // 縦長コンパクトレイアウト
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(NoHighlightButtonStyle())
                .padding(.top, 6)

                switch initialMode {
                case .delayed: delayedContent
                case .interval: intervalContent
                case .changeDetection: changeDetectionContent
                default: EmptyView()
                }
            }
        }
        .frame(width: panelWidth)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func isActiveMode(_ mode: ShutterTab) -> Bool {
        switch mode {
        case .delayed: return shutterService.activeMode == .delayed
        case .interval: return shutterService.activeMode == .interval
        case .changeDetection: return shutterService.activeMode == .changeDetection
        case .programmable: return shutterService.activeMode == .programmable
        }
    }

    // MARK: - Delayed Content

    private var delayedContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            verticalStepper(value: $selectedDelay, range: 1...30, step: 1, format: { "\(Int($0))" }, unit: "秒")

            if shutterService.activeMode == .delayed {
                Text("\(shutterService.countdown)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            captureButton(
                isActive: shutterService.activeMode == .delayed,
                startAction: { onStartDelayed(Int(selectedDelay)) },
                stopAction: onStop
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Interval Content

    private var intervalContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            verticalStepper(value: $selectedInterval, range: 0.5...60, step: 0.5, format: { intervalLabel($0) }, unit: nil)

            Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 8)

            verticalStepper(value: $maxCaptureCount, range: 0...100, step: 1, format: { $0 == 0 ? "∞" : "\(Int($0))" }, unit: "回")

            if shutterService.activeMode == .interval {
                Text("\(shutterService.captureCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            captureButton(
                isActive: shutterService.activeMode == .interval,
                startAction: { onStartInterval(selectedInterval, Int(maxCaptureCount)) },
                stopAction: onStop
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Change Detection Content

    private var changeDetectionContent: some View {
        VStack(spacing: 3) {
            Image(systemName: "eye")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            // 感度 縦スライダー
            Text(formatSensitivity(shutterService.sensitivity))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            verticalSlider(value: $shutterService.sensitivity, range: 0.001...0.20)
                .frame(height: 60)

            // 監視範囲ボタン
            Button(action: {
                if shutterService.monitorSubRect != nil {
                    onResetMonitorRegion?()
                } else {
                    onSelectMonitorRegion?()
                }
            }) {
                Image(systemName: shutterService.monitorSubRect != nil ? "viewfinder.circle.fill" : "viewfinder")
                    .font(.system(size: 14))
                    .foregroundColor(shutterService.monitorSubRect != nil ? .cyan : .white.opacity(0.6))
            }
            .buttonStyle(NoHighlightButtonStyle())

            if shutterService.activeMode == .changeDetection {
                Text(String(format: "%.0f%%", shutterService.currentDiff * 100))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(shutterService.currentDiff > shutterService.sensitivity ? .orange : .cyan)
                Text("\(shutterService.captureCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            captureButton(
                isActive: shutterService.activeMode == .changeDetection,
                startAction: onStartChangeDetection,
                stopAction: onStop
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Programmable Content

    /// ステップ数に応じたプログラマブルパネルの高さを計算
    private func programmableHeight() -> CGFloat {
        // ヘッダー(~30) + パディング(12) + パレット(28) + ボタン(30) + 余白
        let baseHeight: CGFloat = 110
        let stepsHeight = estimateStepsHeight(programSteps)
        let maxHeight: CGFloat = 500
        return min(baseHeight + stepsHeight, maxHeight)
    }

    private func estimateStepsHeight(_ steps: [ProgramStep]) -> CGFloat {
        var h: CGFloat = 0
        for step in steps {
            if step.type == .loop {
                // ループヘッダー + 子要素 + パレット + パディング
                h += 32 + estimateStepsHeight(step.children) + 28 + 12
            } else {
                h += 28
            }
            h += 4 // spacing
        }
        // 末尾ドロップゾーン
        if !steps.isEmpty { h += 20 }
        return h
    }

    private var programmableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
                // ステップリスト
                if !programSteps.isEmpty {
                    ScrollView {
                        VStack(spacing: 4) {
                            stepListView(steps: $programSteps)
                        }
                        .animation(.easeInOut(duration: 0.25), value: allStepIds(programSteps))
                    }
                    .frame(maxHeight: 360)
                } else {
                    Text("ブロックを追加してください")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                }

                // トップレベルパレット（4種すべて）
                stepPalette(steps: $programSteps, includeLoop: true)

                // 実行中ステータス
                if shutterService.activeMode == .programmable {
                    progressBadge {
                        Text("キャプチャ: \(shutterService.captureCount)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                wideActionButton(
                    isActive: shutterService.activeMode == .programmable,
                    startAction: {
                        guard !programSteps.isEmpty else { return }
                        onStartProgrammable(programSteps)
                    },
                    stopAction: onStop
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onChange(of: programSteps) { _ in autoSave() }
    }

    // MARK: - Save Popover

    private var savePopoverContent: some View {
        VStack(spacing: 8) {
            Text("プログラムを保存")
                .font(.system(size: 12, weight: .semibold))
            TextField("名前", text: $saveName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit { performSave() }
            HStack(spacing: 8) {
                Button("キャンセル") { showSavePopover = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func performSave() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ProgramStepStore.saveProgram(name: name, steps: programSteps)
        savedPrograms = ProgramStepStore.loadAllPrograms()
        showSavePopover = false
    }

    private func autoSave() {
        ProgramStepStore.saveLastSteps(programSteps)
    }

    private func assignNewIds(_ steps: [ProgramStep]) -> [ProgramStep] {
        steps.map { step in
            var s = step
            s.id = UUID()
            s.children = assignNewIds(step.children)
            return s
        }
    }

    // MARK: - Recursive Step List

    @ViewBuilder
    private func stepListView(steps: Binding<[ProgramStep]>) -> some View {
        ForEach(Array(steps.wrappedValue.enumerated()), id: \.element.id) { index, step in
            if step.type == .loop {
                AnyView(loopBlockView(steps: steps, index: index))
                    .opacity(draggingStepId == step.id ? 0.3 : 1.0)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
                    .onDrop(of: [.text], delegate: StepDropDelegate(
                        targetId: step.id,
                        rootSteps: $programSteps,
                        draggingStepId: $draggingStepId
                    ))
            } else {
                stepRowView(steps: steps, index: index, step: step)
                    .opacity(draggingStepId == step.id ? 0.3 : 1.0)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
                    .onDrag {
                        draggingStepId = step.id
                        return NSItemProvider(object: step.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: StepDropDelegate(
                        targetId: step.id,
                        rootSteps: $programSteps,
                        draggingStepId: $draggingStepId
                    ))
            }
        }

        // 末尾ドロップゾーン
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .onDrop(of: [.text], delegate: EndOfListDropDelegate(
                targetSteps: steps,
                rootSteps: $programSteps,
                draggingStepId: $draggingStepId
            ))
    }

    @ViewBuilder
    private func loopBlockView(steps: Binding<[ProgramStep]>, index: Int) -> some View {
        let step = steps.wrappedValue[index]
        let isCurrentStep = shutterService.activeMode == .programmable && shutterService.currentStepId == step.id

        VStack(alignment: .leading, spacing: 0) {
            // ループヘッダー行（ドラッグはここだけで開始）
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 10)

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .frame(width: 14)

                Text("繰り返し")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                inlineStepper(
                    value: Binding(
                        get: { Double(steps.wrappedValue[safe: index]?.loopCount ?? 0) },
                        set: { if index < steps.wrappedValue.count { steps.wrappedValue[index].loopCount = Int($0) } }
                    ),
                    range: 0...999, step: 1,
                    format: { $0 == 0 ? "∞" : "\(Int($0))回" },
                    color: .green,
                    fontSize: 13
                )

                // 削除ボタン
                Button(action: {
                    if index < steps.wrappedValue.count {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            steps.wrappedValue.remove(at: index)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            onSizeChange?(CGSize(width: 300, height: programmableHeight()))
                        }
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(NoHighlightButtonStyle())
                .disabled(shutterService.activeMode == .programmable)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .onDrag {
                draggingStepId = step.id
                return NSItemProvider(object: step.id.uuidString as NSString)
            }

            // 子要素エリア
            VStack(spacing: 3) {
                let childrenBinding = Binding<[ProgramStep]>(
                    get: { steps.wrappedValue[safe: index]?.children ?? [] },
                    set: { if index < steps.wrappedValue.count { steps.wrappedValue[index].children = $0 } }
                )

                if steps.wrappedValue[index].children.isEmpty {
                    Text("ブロックを追加")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 3)
                } else {
                    stepListView(steps: childrenBinding)
                }

                // ループ内パレット（繰返含む4種）
                stepPalette(steps: childrenBinding, includeLoop: true)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.25))
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .onDrop(of: [.text], delegate: LoopChildrenDropDelegate(
                loopStepId: step.id,
                rootSteps: $programSteps,
                draggingStepId: $draggingStepId
            ))
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isCurrentStep ? Color.cyan : Color.green.opacity(0.85), lineWidth: isCurrentStep ? 2 : 1)
        )
        .shadow(color: isCurrentStep ? .cyan.opacity(0.6) : .clear, radius: 4)
    }

    @ViewBuilder
    private func stepRowView(steps: Binding<[ProgramStep]>, index: Int, step: ProgramStep) -> some View {
        let isCurrentStep = shutterService.activeMode == .programmable && shutterService.currentStepId == step.id

        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 10)

            Image(systemName: stepIcon(step.type))
                .font(.system(size: 10))
                .foregroundColor(.white)
                .frame(width: 14)

            Text(stepShortLabel(step.type))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 28, alignment: .leading)

            // パラメータ
            switch step.type {
            case .capture:
                Spacer()
            case .wait:
                Spacer()
                inlineStepper(
                    value: Binding(
                        get: { steps.wrappedValue[safe: index]?.waitSeconds ?? 3.0 },
                        set: { if index < steps.wrappedValue.count { steps.wrappedValue[index].waitSeconds = $0 } }
                    ),
                    range: 0.5...999, step: 0.5,
                    format: { waitLabel($0) },
                    color: .orange
                )
            case .waitForChange:
                Slider(value: Binding(
                    get: { (steps.wrappedValue[safe: index]?.sensitivity ?? 0.05) * 100 },
                    set: { if index < steps.wrappedValue.count { steps.wrappedValue[index].sensitivity = $0 / 100 } }
                ), in: 0.1...20, step: 0.1)
                    .controlSize(.mini)
                    .tint(.purple)
                Text(formatSensitivity(step.sensitivity))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 32, alignment: .trailing)

                // 監視範囲ボタン
                Button(action: {
                    if steps.wrappedValue[safe: index]?.monitorSubRect != nil {
                        // リセット
                        if index < steps.wrappedValue.count {
                            steps.wrappedValue[index].monitorSubRect = nil
                        }
                    } else {
                        // 領域選択
                        onSelectStepMonitorRegion? { rect in
                            if index < steps.wrappedValue.count {
                                steps.wrappedValue[index].monitorSubRect = rect
                            }
                        }
                    }
                }) {
                    Image(systemName: step.monitorSubRect != nil ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.system(size: 11))
                        .foregroundColor(step.monitorSubRect != nil ? .cyan : .white.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(NoHighlightButtonStyle())
                .disabled(shutterService.activeMode == .programmable)
            case .waitForStable:
                Slider(value: Binding(
                    get: { (steps.wrappedValue[safe: index]?.sensitivity ?? 0.05) * 100 },
                    set: { if index < steps.wrappedValue.count { steps.wrappedValue[index].sensitivity = $0 / 100 } }
                ), in: 0.1...20, step: 0.1)
                    .controlSize(.mini)
                    .tint(.yellow)
                Text(formatSensitivity(step.sensitivity))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 32, alignment: .trailing)

                // 監視範囲ボタン
                Button(action: {
                    if steps.wrappedValue[safe: index]?.monitorSubRect != nil {
                        if index < steps.wrappedValue.count {
                            steps.wrappedValue[index].monitorSubRect = nil
                        }
                    } else {
                        onSelectStepMonitorRegion? { rect in
                            if index < steps.wrappedValue.count {
                                steps.wrappedValue[index].monitorSubRect = rect
                            }
                        }
                    }
                }) {
                    Image(systemName: step.monitorSubRect != nil ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.system(size: 11))
                        .foregroundColor(step.monitorSubRect != nil ? .cyan : .white.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(NoHighlightButtonStyle())
                .disabled(shutterService.activeMode == .programmable)
            default:
                EmptyView()
            }

            // 削除ボタン
            Button(action: {
                if index < steps.wrappedValue.count {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        steps.wrappedValue.remove(at: index)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        onSizeChange?(CGSize(width: 300, height: programmableHeight()))
                    }
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(NoHighlightButtonStyle())
            .disabled(shutterService.activeMode == .programmable)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(stepColor(step.type).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrentStep ? Color.cyan : stepColor(step.type).opacity(0.85), lineWidth: isCurrentStep ? 2 : 1)
        )
        .shadow(color: isCurrentStep ? .cyan.opacity(0.6) : .clear, radius: 4)
    }

    // MARK: - Step Palette

    @ViewBuilder
    private func stepPalette(steps: Binding<[ProgramStep]>, includeLoop: Bool) -> some View {
        HStack(spacing: 4) {
            paletteButton(steps: steps, type: .capture, icon: "camera.fill", label: "撮影")
            paletteButton(steps: steps, type: .wait, icon: "clock", label: "待機")
            paletteButton(steps: steps, type: .waitForChange, icon: "eye", label: "変化")
            paletteButton(steps: steps, type: .waitForStable, icon: "eye.trianglebadge.exclamationmark", label: "安定")
            if includeLoop {
                paletteButton(steps: steps, type: .loop, icon: "arrow.counterclockwise", label: "繰返")
            }
        }
        .disabled(shutterService.activeMode == .programmable)
    }

    private func stepShortLabel(_ type: ProgramStepType) -> String {
        switch type {
        case .capture:       return "撮影"
        case .wait:          return "待機"
        case .waitForChange: return "変化"
        case .waitForStable: return "安定"
        case .loop:          return "繰返"
        }
    }

    @ViewBuilder
    private func paletteButton(steps: Binding<[ProgramStep]>, type: ProgramStepType, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                steps.wrappedValue.append(ProgramStep(type: type))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                onSizeChange?(CGSize(width: 300, height: programmableHeight()))
            }
        }) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    private func stepIcon(_ type: ProgramStepType) -> String {
        switch type {
        case .capture: return "camera.fill"
        case .wait: return "clock"
        case .waitForChange: return "eye"
        case .waitForStable: return "eye.trianglebadge.exclamationmark"
        case .loop: return "arrow.counterclockwise"
        }
    }

    private func stepColor(_ type: ProgramStepType) -> Color {
        switch type {
        case .capture:        return .cyan
        case .wait:           return .orange
        case .waitForChange:  return .purple
        case .waitForStable:  return .yellow
        case .loop:           return .green
        }
    }

    private func waitLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds / 60))分"
        } else if seconds == floor(seconds) {
            return "\(Int(seconds))秒"
        } else {
            return String(format: "%.1f秒", seconds)
        }
    }

    private func formatSensitivity(_ value: Double) -> String {
        let pct = value * 100
        if pct >= 1 {
            return "\(Int(pct))%"
        } else {
            return String(format: "%.1f%%", pct)
        }
    }

    /// 全ステップのIDをフラットに収集（アニメーション監視用）
    private func allStepIds(_ steps: [ProgramStep]) -> [UUID] {
        steps.flatMap { step in
            [step.id] + allStepIds(step.children)
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func progressBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule()
                    .fill(Color.cyan.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    @ViewBuilder
    private func captureButton(isActive: Bool, startAction: @escaping () -> Void, stopAction: @escaping () -> Void) -> some View {
        Button(action: {
            if isActive { stopAction() } else { startAction() }
        }) {
            ZStack {
                Circle()
                    .strokeBorder(isActive ? Color.red : Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 28, height: 28)

                if isActive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.5), radius: 4, x: 0, y: 1)
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .shadow(color: .cyan.opacity(0.5), radius: 4, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    @ViewBuilder
    private func wideActionButton(isActive: Bool, startAction: @escaping () -> Void, stopAction: @escaping () -> Void) -> some View {
        Button(action: {
            if isActive { stopAction() } else { startAction() }
        }) {
            Text(isActive ? "停止" : "開始")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isActive
                                ? LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [.cyan, .blue.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        )
                )
                .shadow(color: isActive ? .red.opacity(0.4) : .cyan.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(NoHighlightButtonStyle())
    }

    @ViewBuilder
    private func verticalStepper(value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String, unit: String?) -> some View {
        VStack(spacing: 1) {
            Button(action: {
                let newVal = value.wrappedValue + step
                if newVal <= range.upperBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 28, height: 14)
            }
            .buttonStyle(NoHighlightButtonStyle())

            Text(format(value.wrappedValue))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))

            if let unit = unit {
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
            }

            Button(action: {
                let newVal = value.wrappedValue - step
                if newVal >= range.lowerBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 28, height: 14)
            }
            .buttonStyle(NoHighlightButtonStyle())
        }
    }

    @ViewBuilder
    private func verticalSlider(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        GeometryReader { geo in
            let trackH = geo.size.height
            let fraction = (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbY = trackH * (1 - fraction)

            ZStack(alignment: .bottom) {
                // トラック
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                // アクティブ部分
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.cyan.opacity(0.6))
                    .frame(width: 4, height: trackH * fraction)
            }
            .frame(maxWidth: .infinity)
            .overlay(
                // つまみ
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                    .shadow(color: .cyan.opacity(0.4), radius: 3)
                    .position(x: geo.size.width / 2, y: thumbY)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = max(0, min(trackH, drag.location.y))
                        let frac = 1 - (y / trackH)
                        value.wrappedValue = range.lowerBound + (range.upperBound - range.lowerBound) * frac
                    }
            )
        }
        .frame(width: 20)
    }

    private func inlineStepper(value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String, color: Color, fontSize: CGFloat = 10) -> some View {
        InlineStepperView(value: value, range: range, step: step, format: format, color: color, fontSize: fontSize)
    }

    @ViewBuilder
    private func stepperRow(value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                let newVal = value.wrappedValue - step
                if newVal >= range.lowerBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(NoHighlightButtonStyle())

            Text(format(value.wrappedValue))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(minWidth: 32)

            Button(action: {
                let newVal = value.wrappedValue + step
                if newVal <= range.upperBound { value.wrappedValue = newVal }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(NoHighlightButtonStyle())
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func intervalLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds / 60))分"
        } else if seconds == floor(seconds) {
            return "\(Int(seconds))秒"
        } else {
            return String(format: "%.1f秒", seconds)
        }
    }
}

// MARK: - Window Controller

@MainActor
class ShutterOptionsPanelController {
    let shutterService = ShutterService()
    var onCloseRequested: (() -> Void)?
    private var window: NSWindow?
    private var parentWindow: NSWindow?
    private var frameObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var cachedSize: CGSize?
    private var captureRegion: CGRect = .zero
    private let monitorRegionOverlay = MonitorRegionOverlay()
    private let monitorRegionIndicator = MonitorRegionIndicator()
    private var changeDetectionObserver: NSObjectProtocol?

    func show(attachedTo parent: NSWindow, screenshot: Screenshot, mode: ShutterTab, onRecapture: @escaping (CGRect, NSWindow?) -> Void) {
        parentWindow = parent
        captureRegion = screenshot.captureRegion ?? .zero

        // Set up the capture callback
        shutterService.onCapture = { [weak self] in
            guard let self = self, let parent = self.parentWindow else { return }
            let rect = self.contentCGRegion(of: parent)
            onRecapture(rect, parent)
        }

        let panelView = ShutterOptionsView(
            shutterService: shutterService,
            onStartDelayed: { [weak self] seconds in
                self?.shutterService.startDelayed(seconds: seconds)
            },
            onStartInterval: { [weak self] seconds, maxCount in
                self?.shutterService.startInterval(seconds: seconds, maxCount: maxCount)
            },
            onStartChangeDetection: { [weak self] in
                guard let self = self else { return }
                self.shutterService.startChangeDetection(
                    regionProvider: { [weak self] in
                        self?.currentCGRegion() ?? .zero
                    }
                )
                self.showIndicatorIfNeeded()
            },
            onStartProgrammable: { [weak self] steps in
                guard let self = self else { return }
                self.shutterService.startProgrammable(
                    steps: steps,
                    regionProvider: { [weak self] in
                        self?.currentCGRegion() ?? .zero
                    }
                )
                self.showIndicatorIfNeeded()
            },
            onStop: { [weak self] in
                self?.shutterService.stopAll()
                self?.monitorRegionIndicator.dismiss()
            },
            onClose: { [weak self] in
                self?.onCloseRequested?()
            },
            onSelectMonitorRegion: { [weak self] in
                self?.startMonitorRegionSelection()
            },
            onResetMonitorRegion: { [weak self] in
                self?.shutterService.monitorSubRect = nil
                self?.monitorRegionIndicator.dismiss()
            },
            onSelectStepMonitorRegion: { [weak self] completion in
                self?.startStepMonitorRegionSelection(completion: completion)
            },
            onSizeChange: { [weak self] newSize in
                self?.updatePanelSize(newSize)
            },
            initialMode: mode
        )

        let panelSize = ShutterOptionsView.panelSize(for: mode)
        cachedSize = panelSize

        // プログラマブルはコンテンツが伸びるので、hostingは最大サイズで確保
        let maxHostingSize = mode == .programmable
            ? CGSize(width: 300, height: 500)
            : panelSize

        let wrappedView = VStack(spacing: 0) {
            panelView
            Spacer(minLength: 0)
        }
        .frame(width: maxHostingSize.width, height: maxHostingSize.height, alignment: .top)

        let hosting = NSHostingView(rootView: wrappedView)
        hosting.layer?.isOpaque = false

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hosting.frame = NSRect(x: 0, y: 0, width: maxHostingSize.width, height: maxHostingSize.height)
        hosting.autoresizingMask = []
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        self.window = window

        updatePosition()
        parent.addChildWindow(window, ordered: .above)

        // Fade-in animation
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        // Observe parent window movement and resize
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    func close() {
        shutterService.stopAll()
        monitorRegionOverlay.dismiss()
        monitorRegionIndicator.dismiss()

        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let observer = changeDetectionObserver {
            NotificationCenter.default.removeObserver(observer)
            changeDetectionObserver = nil
        }
        if let panelWindow = window, let parent = parentWindow {
            parent.removeChildWindow(panelWindow)
        }
        window?.orderOut(nil)
        window = nil
        parentWindow = nil
        cachedSize = nil
    }

    func toggle(attachedTo parent: NSWindow, screenshot: Screenshot, mode: ShutterTab, onRecapture: @escaping (CGRect, NSWindow?) -> Void) {
        if window != nil {
            close()
        } else {
            show(attachedTo: parent, screenshot: screenshot, mode: mode, onRecapture: onRecapture)
        }
    }

    /// parentWindow の現在位置からCG座標系のリージョンを返す
    func currentCGRegion() -> CGRect {
        guard let parent = parentWindow else { return captureRegion }
        return contentCGRegion(of: parent)
    }

    /// ウィンドウのコンテンツ領域をCG座標系で返す（リサイズマージンを除外）
    private func contentCGRegion(of window: NSWindow) -> CGRect {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        // contentLayoutRect はウィンドウローカル座標のコンテンツ領域
        let content = window.contentLayoutRect
        // ウィンドウ座標系でのコンテンツ原点をスクリーン座標に変換
        let contentOriginInScreen = NSPoint(
            x: window.frame.origin.x + content.origin.x,
            y: window.frame.origin.y + content.origin.y
        )
        return CGRect(
            x: contentOriginInScreen.x,
            y: screenHeight - contentOriginInScreen.y - content.height,
            width: content.width,
            height: content.height
        )
    }

    private func updatePanelSize(_ newSize: CGSize) {
        cachedSize = newSize
        guard let panel = window else { return }
        let oldFrame = panel.frame
        let newY = oldFrame.maxY - newSize.height
        let newFrame = NSRect(x: oldFrame.origin.x, y: newY, width: newSize.width, height: newSize.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    private func updatePosition() {
        guard let parent = parentWindow, let panel = window else { return }

        let parentFrame = parent.frame
        let panelSize = cachedSize ?? CGSize(width: 200, height: 250)

        // Place to the right of the parent window
        var panelX = parentFrame.maxX + 4
        var panelY = parentFrame.maxY - panelSize.height

        if let screen = parent.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame

            // If no room on the right, place on the left
            if panelX + panelSize.width > screenFrame.maxX {
                panelX = parentFrame.minX - panelSize.width - 4
            }

            // Clamp to screen bounds
            if panelX < screenFrame.minX {
                panelX = screenFrame.minX
            }
            if panelY < screenFrame.minY {
                panelY = screenFrame.minY
            }
            if panelY + panelSize.height > screenFrame.maxY {
                panelY = screenFrame.maxY - panelSize.height
            }
        }

        panel.setFrame(
            NSRect(x: panelX, y: panelY, width: panelSize.width, height: panelSize.height),
            display: false
        )
    }

    private func startStepMonitorRegionSelection(completion: @escaping (CGRect?) -> Void) {
        guard let parent = parentWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.monitorRegionOverlay.show(on: parent) { normalizedRect in
                completion(normalizedRect)
            }
        }
    }

    private func startMonitorRegionSelection() {
        guard let parent = parentWindow else { return }
        // SwiftUIのボタンコールバック内からウィンドウ生成すると不安定なので遅延実行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.monitorRegionOverlay.show(on: parent) { [weak self] normalizedRect in
                guard let self = self else { return }
                if let rect = normalizedRect {
                    self.shutterService.monitorSubRect = rect
                    self.showIndicatorIfNeeded()
                }
            }
        }
    }

    private func showIndicatorIfNeeded() {
        guard let parent = parentWindow,
              let subRect = shutterService.monitorSubRect else {
            monitorRegionIndicator.dismiss()
            return
        }
        monitorRegionIndicator.show(on: parent, normalizedRect: subRect)
    }
}

// MARK: - Monitor Region Overlay (ドラッグで監視サブ領域を選択)

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.sharingType = .none
    }
}

private class MonitorRegionKeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.sharingType = .none
    }
}

@MainActor
class MonitorRegionOverlay {
    private var overlayWindow: NSWindow?
    private weak var parentWindow: NSWindow?
    private var selectionView: MonitorRegionSelectionView?
    private var cursorPushed = false

    func show(on parentWindow: NSWindow, completion: @escaping (CGRect?) -> Void) {
        dismiss()
        self.parentWindow = parentWindow
        let parentFrame = parentWindow.frame

        let window = MonitorRegionKeyableWindow(
            contentRect: parentFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = MonitorRegionSelectionView(
            frame: NSRect(origin: .zero, size: parentFrame.size)
        ) { [weak self] rect in
            guard let self = self else { return }
            let normalized = CGRect(
                x: rect.origin.x / parentFrame.width,
                y: rect.origin.y / parentFrame.height,
                width: rect.width / parentFrame.width,
                height: rect.height / parentFrame.height
            )
            // dismiss後にcompletionを呼ぶ（ウィンドウ解放とコールバックを分離）
            self.dismiss()
            DispatchQueue.main.async {
                completion(normalized)
            }
        } onCancel: { [weak self] in
            self?.dismiss()
            DispatchQueue.main.async {
                completion(nil)
            }
        }
        self.selectionView = view

        window.contentView = view
        self.overlayWindow = window

        // 親の子ウィンドウとして追加（親のキー状態を維持）
        parentWindow.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        cursorPushed = true
        NSCursor.crosshair.push()
    }

    func dismiss() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        if let w = overlayWindow, let parent = parentWindow {
            parent.removeChildWindow(w)
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        selectionView = nil
    }
}

private class MonitorRegionSelectionView: NSView {
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect?
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateSelectionRect()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let rect = selectionRect, rect.width > 10, rect.height > 10 {
            onComplete(rect)
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        }
    }

    private func updateSelectionRect() {
        guard let start = startPoint, let current = currentPoint else { return }
        selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 半透明オーバーレイ
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }

        // 選択領域をくり抜き
        NSColor.clear.set()
        rect.fill(using: .copy)

        // シアンの枠線
        NSColor.cyan.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // サイズ表示
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        var labelRect = CGRect(
            x: rect.midX - size.width / 2 - padding,
            y: rect.maxY + 6,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        if labelRect.maxY > bounds.maxY - 10 {
            labelRect.origin.y = rect.minY - labelRect.height - 6
        }
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + padding, y: labelRect.minY + padding / 2),
            withAttributes: attributes
        )
    }
}

// MARK: - Monitor Region Indicator (監視中のサブ領域枠線表示)

@MainActor
class MonitorRegionIndicator {
    private var indicatorWindow: NSWindow?

    func show(on parentWindow: NSWindow, normalizedRect: CGRect) {
        dismiss()

        let parentFrame = parentWindow.frame
        // 正規化座標→NS座標に変換（NSWindowは左下原点）
        let subX = parentFrame.origin.x + parentFrame.width * normalizedRect.origin.x
        let subY = parentFrame.origin.y + parentFrame.height * (1 - normalizedRect.origin.y - normalizedRect.height)
        let subW = parentFrame.width * normalizedRect.width
        let subH = parentFrame.height * normalizedRect.height

        let frame = NSRect(x: subX, y: subY, width: subW, height: subH)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .none

        let borderView = MonitorRegionBorderView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = borderView

        parentWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        self.indicatorWindow = window
    }

    func dismiss() {
        if let w = indicatorWindow {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
        }
        indicatorWindow = nil
    }

    func updatePosition(on parentWindow: NSWindow, normalizedRect: CGRect) {
        guard let window = indicatorWindow else { return }
        let parentFrame = parentWindow.frame
        let subX = parentFrame.origin.x + parentFrame.width * normalizedRect.origin.x
        let subY = parentFrame.origin.y + parentFrame.height * (1 - normalizedRect.origin.y - normalizedRect.height)
        let subW = parentFrame.width * normalizedRect.width
        let subH = parentFrame.height * normalizedRect.height
        window.setFrame(NSRect(x: subX, y: subY, width: subW, height: subH), display: true)
    }
}

private class MonitorRegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.cyan.withAlphaComponent(0.8).setStroke()
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}

// MARK: - Step Drop Delegate

struct StepDropDelegate: DropDelegate {
    let targetId: UUID
    let rootSteps: Binding<[ProgramStep]>
    @Binding var draggingStepId: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingStepId, dragId != targetId else { return }
        // ルートから再帰的にドラッグ元を取り出す
        guard let draggedStep = Self.removeStep(id: dragId, from: &rootSteps.wrappedValue) else { return }
        // ターゲットの前に挿入
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = Self.insertStep(draggedStep, before: targetId, in: &rootSteps.wrappedValue)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingStepId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    // 再帰的にステップを検索・削除して返す
    static func removeStep(id: UUID, from steps: inout [ProgramStep]) -> ProgramStep? {
        if let index = steps.firstIndex(where: { $0.id == id }) {
            return steps.remove(at: index)
        }
        for i in steps.indices {
            if let found = removeStep(id: id, from: &steps[i].children) {
                return found
            }
        }
        return nil
    }

    // targetIdの前に挿入
    static func insertStep(_ step: ProgramStep, before targetId: UUID, in steps: inout [ProgramStep]) -> Bool {
        if let index = steps.firstIndex(where: { $0.id == targetId }) {
            steps.insert(step, at: index)
            return true
        }
        for i in steps.indices {
            if insertStep(step, before: targetId, in: &steps[i].children) {
                return true
            }
        }
        return false
    }
}

// MARK: - Loop Children Drop Delegate

struct LoopChildrenDropDelegate: DropDelegate {
    let loopStepId: UUID
    let rootSteps: Binding<[ProgramStep]>
    @Binding var draggingStepId: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingStepId, dragId != loopStepId else { return }
        // すでにこのループの直下にある場合はスキップ（子要素のStepDropDelegateに任せる）
        if Self.findStep(id: loopStepId, in: rootSteps.wrappedValue)?.children.contains(where: { $0.id == dragId }) == true {
            return
        }
        // ルートから削除
        guard let draggedStep = StepDropDelegate.removeStep(id: dragId, from: &rootSteps.wrappedValue) else { return }
        // ループの children 末尾に追加
        withAnimation(.easeInOut(duration: 0.2)) {
            Self.appendToLoop(step: draggedStep, loopId: loopStepId, in: &rootSteps.wrappedValue)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingStepId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    private static func findStep(id: UUID, in steps: [ProgramStep]) -> ProgramStep? {
        for step in steps {
            if step.id == id { return step }
            if let found = findStep(id: id, in: step.children) { return found }
        }
        return nil
    }

    private static func appendToLoop(step: ProgramStep, loopId: UUID, in steps: inout [ProgramStep]) {
        for i in steps.indices {
            if steps[i].id == loopId {
                steps[i].children.append(step)
                return
            }
            appendToLoop(step: step, loopId: loopId, in: &steps[i].children)
        }
    }
}

// MARK: - End of List Drop Delegate

struct EndOfListDropDelegate: DropDelegate {
    let targetSteps: Binding<[ProgramStep]>
    let rootSteps: Binding<[ProgramStep]>
    @Binding var draggingStepId: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragId = draggingStepId else { return }
        // すでにこの配列の末尾なら何もしない
        if targetSteps.wrappedValue.last?.id == dragId { return }
        guard let step = StepDropDelegate.removeStep(id: dragId, from: &rootSteps.wrappedValue) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            targetSteps.wrappedValue.append(step)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingStepId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Inline Stepper View

private struct InlineStepperView: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let color: Color
    let fontSize: CGFloat

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button(action: {
                let newVal = value - step
                if newVal >= range.lowerBound { value = newVal }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color.opacity(0.9))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(color.opacity(0.15)))
            }
            .buttonStyle(NoHighlightButtonStyle())

            if isEditing {
                TextField("", text: $editText, onCommit: commitEdit)
                    .focused($isFocused)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 36, maxWidth: 50)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.15))
                    )
                    .onChange(of: isFocused) { focused in
                        if !focused { commitEdit() }
                    }
                    .onAppear { isFocused = true }
            } else {
                Text(format(value))
                    .font(.system(size: displayFontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minWidth: 30)
                    .contentShape(Rectangle())
                    .onTapGesture { startEditing() }
            }

            Button(action: {
                let newVal = value + step
                if newVal <= range.upperBound { value = newVal }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color.opacity(0.9))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(color.opacity(0.15)))
            }
            .buttonStyle(NoHighlightButtonStyle())
        }
    }

    /// ∞ 表示時はフォントサイズを大きめにする
    private var displayFontSize: CGFloat {
        format(value) == "∞" ? fontSize + 4 : fontSize
    }

    private func startEditing() {
        // 編集開始時は生の数値を表示
        if step >= 1 {
            editText = value == 0 && range.lowerBound == 0 ? "" : "\(Int(value))"
        } else {
            editText = value == 0 ? "" : String(format: "%g", value)
        }
        isEditing = true
    }

    private func commitEdit() {
        let stripped = editText.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        if let parsed = Double(stripped) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            if step >= 1 {
                value = Double(Int(clamped))
            } else {
                value = (clamped / step).rounded() * step
            }
        } else if editText.trimmingCharacters(in: .whitespaces).isEmpty {
            // 空欄 → 最小値（ループの場合は0=∞になる）
            value = range.lowerBound
        }
        isEditing = false
    }
}

// MARK: - Safe Array Access

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
