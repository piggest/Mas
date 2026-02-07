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
        .frame(width: 450, height: 380)
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

            Spacer()
        }
        .padding()
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
                .frame(width: 180, alignment: .leading)
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
    var body: some View {
        Form {
            Section("キャプチャショートカット") {
                HStack {
                    Text("全画面キャプチャ")
                    Spacer()
                    Text("⌘⇧3")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }

                HStack {
                    Text("範囲選択キャプチャ")
                    Spacer()
                    Text("⌘⇧4")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }

            }

            Section {
                Text("ショートカットは現在固定されています")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
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

            Spacer()
        }
        .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .leading)
            content()
        }
    }
}
