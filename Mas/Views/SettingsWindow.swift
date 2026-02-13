import SwiftUI

struct SettingsWindow: View {
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("一般", systemImage: "gear")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("ショートカット", systemImage: "keyboard")
                }

            if developerMode {
                DeveloperSettingsView()
                    .tabItem {
                        Label("開発", systemImage: "wrench.and.screwdriver")
                    }
            }

            AboutView()
                .tabItem {
                    Label("情報", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 480)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultFormat") private var defaultFormat = "PNG"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    @AppStorage("showCursor") private var showCursor = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled = true
    @AppStorage("autoSaveFolder") private var autoSaveFolder = ""
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = true
    @AppStorage("closeOnDragSuccess") private var closeOnDragSuccess = true
    @AppStorage("pinBehavior") private var pinBehavior = "alwaysOn"
    @AppStorage("developerMode") private var developerMode = false
    @State private var displayPath = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("キャプチャ")
                VStack(alignment: .leading, spacing: 8) {
                    settingRow("クリップボードにコピー") {
                        Toggle("", isOn: $autoCopyToClipboard).labelsHidden()
                    }
                    settingRow("ファイルに保存") {
                        Toggle("", isOn: $autoSaveEnabled).labelsHidden()
                    }
                    if autoSaveEnabled {
                        settingRow("保存先") {
                            HStack {
                                Text(displayPath.isEmpty ? "~/Pictures/Mas" : displayPath)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("変更...") { selectFolder() }
                                    .controlSize(.small)
                            }
                        }
                        settingRow("保存形式") {
                            Picker("", selection: $defaultFormat) {
                                Text("PNG").tag("PNG")
                                Text("JPEG").tag("JPEG")
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        if defaultFormat == "JPEG" {
                            settingRow("JPEG品質") {
                                HStack {
                                    Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                                    Text("\(Int(jpegQuality * 100))%")
                                        .monospacedDigit()
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                Divider()

                sectionHeader("ウィンドウ")
                VStack(alignment: .leading, spacing: 8) {
                    settingRow("ピン（最前面表示）") {
                        Picker("", selection: $pinBehavior) {
                            Text("常にON").tag("alwaysOn")
                            Text("最新のみON").tag("latestOnly")
                            Text("デフォルトOFF").tag("off")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    settingRow("ドラッグ成功時に閉じる") {
                        Toggle("", isOn: $closeOnDragSuccess).labelsHidden()
                    }
                }

                Divider()

                Group {
                    sectionHeader("メニューバー")
                    settingRow("アイコン") {
                        MenuBarIconPicker()
                    }

                    Divider()

                    sectionHeader("その他")
                    VStack(alignment: .leading, spacing: 8) {
                        settingRow("マウスカーソルを含める") {
                            Toggle("", isOn: $showCursor).labelsHidden()
                        }
                        settingRow("キャプチャ時にサウンド再生") {
                            Toggle("", isOn: $playSound).labelsHidden()
                        }
                        settingRow("開発者モード") {
                            Toggle("", isOn: $developerMode).labelsHidden()
                        }
                    }

                    Divider()

                    UpdateSettingsSection()
                }
            }
            .padding()
        }
        .onAppear {
            updateDisplayPath()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .trailing)
            content()
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            autoSaveFolder = url.path
            updateDisplayPath()
        }
    }

    private func updateDisplayPath() {
        if autoSaveFolder.isEmpty {
            displayPath = ""
        } else {
            // ホームディレクトリを~に置換
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if autoSaveFolder.hasPrefix(home) {
                displayPath = autoSaveFolder.replacingOccurrences(of: home, with: "~")
            } else {
                displayPath = autoSaveFolder
            }
        }
    }
}

struct ShortcutsSettingsView: View {
    @State private var recordingAction: HotkeyAction?
    @State private var refreshTrigger = false
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("ショートカットキー")
            Text("クリックしてからキーを入力すると変更できます")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(HotkeyAction.allCases, id: \.rawValue) { action in
                    shortcutRow(action: action)
                }
            }

            if let conflict = conflictMessage {
                Text(conflict)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            HStack {
                Button("すべてデフォルトに戻す") {
                    for action in HotkeyAction.allCases {
                        action.resetToDefault()
                    }
                    recordingAction = nil
                    conflictMessage = nil
                    refreshTrigger.toggle()
                    NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding()
        .id(refreshTrigger)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
    }

    private func shortcutRow(action: HotkeyAction) -> some View {
        HStack {
            Text(action.label)
                .frame(width: 160, alignment: .trailing)

            KeyRecorderButton(
                action: action,
                isRecording: recordingAction == action,
                onStartRecording: {
                    recordingAction = action
                    conflictMessage = nil
                },
                onKeyRecorded: { keyCode, modifiers in
                    // 競合チェック
                    for other in HotkeyAction.allCases where other != action {
                        if other.keyCode == keyCode && other.modifiers == modifiers {
                            conflictMessage = "「\(other.label)」と同じキーです"
                            recordingAction = nil
                            return
                        }
                    }
                    action.save(keyCode: keyCode, modifiers: modifiers)
                    recordingAction = nil
                    conflictMessage = nil
                    refreshTrigger.toggle()
                    NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
                },
                onCancel: {
                    recordingAction = nil
                }
            )

            if action.isCustomized {
                Button(action: {
                    action.resetToDefault()
                    refreshTrigger.toggle()
                    NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("デフォルトに戻す")
            }

            Spacer()
        }
    }
}

struct KeyRecorderButton: View {
    let action: HotkeyAction
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onKeyRecorded: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    var body: some View {
        if isRecording {
            KeyRecorderView(onKeyRecorded: onKeyRecorded, onCancel: onCancel)
                .frame(width: 140, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
        } else {
            Button(action: onStartRecording) {
                Text(action.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 140, height: 24)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// NSViewRepresentableでキー入力をキャッチするビュー
struct KeyRecorderView: NSViewRepresentable {
    let onKeyRecorded: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = onKeyRecorded
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {}
}

class KeyRecorderNSView: NSView {
    var onKeyRecorded: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?
    private var currentModifiers: UInt32 = 0
    private let label = NSTextField(labelWithString: "キーを入力...")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escキーでキャンセル
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let modifiers = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)

        // 修飾キーが最低1つ必要
        if modifiers == 0 {
            label.stringValue = "修飾キー+キー"
            return
        }

        onKeyRecorded?(UInt32(event.keyCode), modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        currentModifiers = UInt32(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        if currentModifiers != 0 {
            label.stringValue = HotkeyDisplayHelper.modifiersDisplayString(currentModifiers) + "..."
        } else {
            label.stringValue = "キーを入力..."
        }
    }

    override func becomeFirstResponder() -> Bool {
        label.stringValue = "キーを入力..."
        return true
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()
        return true
    }
}

struct MenuBarIconPicker: View {
    @AppStorage("menuBarIconStyle") private var menuBarIconStyle = "appIcon"

    private let options: [(id: String, label: String)] = [
        ("appIcon", "Mas"),
        ("diamond", "モノクロ"),
        ("camera", "カメラ"),
        ("screenshot", "枠"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.id) { option in
                Button(action: {
                    menuBarIconStyle = option.id
                    NotificationCenter.default.post(name: .menuBarIconChanged, object: nil)
                }) {
                    VStack(spacing: 3) {
                        iconPreview(option.id)
                            .frame(width: 22, height: 22)
                        Text(option.label)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .frame(width: 56, height: 48)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(menuBarIconStyle == option.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(menuBarIconStyle == option.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: menuBarIconStyle == option.id ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func iconPreview(_ style: String) -> some View {
        switch style {
        case "diamond":
            Image("MenuBarIconCustom")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .colorInvert()
        case "camera":
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 16))
        case "screenshot":
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 16))
        default: // appIcon
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)

            Text("Mas")
                .font(.title)
                .fontWeight(.bold)

            Text("Mac Area Screenshot")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("バージョン \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("まるでマスですくうように\n簡単に正確にスクリーンショットを作成します")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()

            Text("© 2026")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct DeveloperSettingsView: View {
    @AppStorage("includeOwnUI") private var includeOwnUI = false
    @State private var captureDelay: Double = 3
    @State private var countdownRemaining: Int?

    private var dataFolderURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Mas")
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = dataFolderURL.path
        if path.hasPrefix(home) {
            return path.replacingOccurrences(of: home, with: "~")
        }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("データ")
            VStack(alignment: .leading, spacing: 8) {
                settingRow("データフォルダ") {
                    HStack {
                        Text(displayPath)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Finderで開く") {
                            NSWorkspace.shared.open(dataFolderURL)
                        }
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            sectionHeader("キャプチャ")
            VStack(alignment: .leading, spacing: 8) {
                settingRow("自UIをキャプチャに含める") {
                    Toggle("", isOn: $includeOwnUI)
                        .labelsHidden()
                        .onChange(of: includeOwnUI) { _ in
                            NSWindow.updateAllMasSharingType()
                        }
                }
                Text("ONにするとMasのボタンや枠線もスクリーンショットに映ります")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 180)
            }

            Divider()

            sectionHeader("遅延キャプチャ")
            Text("メニューやライブラリなど、通常キャプチャしづらいUI要素を撮影できます")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                settingRow("遅延時間") {
                    HStack {
                        Slider(value: $captureDelay, in: 1...10, step: 1)
                            .frame(width: 120)
                        Text("\(Int(captureDelay))秒")
                            .frame(width: 30)
                    }
                }
                settingRow("") {
                    HStack(spacing: 8) {
                        Button("全画面キャプチャ") {
                            startDelayedCapture(notification: .captureFullScreen)
                        }
                        .controlSize(.small)
                        .disabled(countdownRemaining != nil)

                        Button("範囲選択キャプチャ") {
                            startDelayedCapture(notification: .captureRegion)
                        }
                        .controlSize(.small)
                        .disabled(countdownRemaining != nil)

                        if let remaining = countdownRemaining {
                            Text("\(remaining)秒後にキャプチャ...")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private func startDelayedCapture(notification: Notification.Name) {
        let delay = Int(captureDelay)
        countdownRemaining = delay

        // 設定ウィンドウを閉じる
        NSApp.windows.filter { $0.title.contains("設定") || $0.contentViewController is NSHostingController<SettingsWindow> }.forEach { $0.close() }

        // カウントダウン
        for i in 0..<delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [self] in
                countdownRemaining = delay - i
            }
        }

        // 遅延後にキャプチャ実行
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
            countdownRemaining = nil
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .trailing)
            content()
        }
    }
}

struct UpdateSettingsSection: View {
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled = false
    @StateObject private var updateService = UpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("アップデート")
                .font(.system(size: 13, weight: .bold))

            settingRow("自動アップデート") {
                Toggle("", isOn: $autoUpdateEnabled)
                    .labelsHidden()
                    .onChange(of: autoUpdateEnabled) { newValue in
                        if newValue {
                            updateService.startPeriodicCheck()
                        } else {
                            updateService.stopPeriodicCheck()
                        }
                    }
            }

            settingRow("") {
                HStack(spacing: 8) {
                    Button("今すぐ確認") {
                        Task {
                            await updateService.checkForUpdate()
                        }
                    }
                    .controlSize(.small)
                    .disabled(isActionInProgress)

                    statusView
                }
            }
        }
    }

    private var isActionInProgress: Bool {
        switch updateService.status {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch updateService.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("確認中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .available(let version):
            HStack(spacing: 8) {
                Text("v\(version) が利用可能")
                    .font(.caption)
                    .foregroundColor(.orange)
                Button("アップデート") {
                    Task {
                        await updateService.downloadAndInstall()
                    }
                }
                .controlSize(.small)
            }
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("ダウンロード中... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .installing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("インストール中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .readyToRestart:
            HStack(spacing: 8) {
                Text("インストール完了")
                    .font(.caption)
                    .foregroundColor(.green)
                Button("再起動") {
                    updateService.restart()
                }
                .controlSize(.small)
            }
        case .upToDate:
            Text("最新バージョンです")
                .font(.caption)
                .foregroundColor(.green)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .trailing)
            content()
        }
    }
}
