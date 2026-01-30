import SwiftUI

struct SettingsWindow: View {
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

            AboutView()
                .tabItem {
                    Label("情報", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
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
    @State private var displayPath = ""

    var body: some View {
        Form {
            Section("キャプチャ時の動作") {
                Toggle("クリップボードにコピー", isOn: $autoCopyToClipboard)
                Toggle("ファイルに保存", isOn: $autoSaveEnabled)

                if autoSaveEnabled {
                    HStack {
                        Text("保存先")
                        Spacer()
                        Text(displayPath.isEmpty ? "~/Pictures/Mas" : displayPath)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("変更...") {
                            selectFolder()
                        }
                    }
                }
            }

            Section("保存形式") {
                Picker("デフォルト保存形式", selection: $defaultFormat) {
                    Text("PNG").tag("PNG")
                    Text("JPEG").tag("JPEG")
                }

                if defaultFormat == "JPEG" {
                    HStack {
                        Text("JPEG品質")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.1)
                        Text("\(Int(jpegQuality * 100))%")
                            .frame(width: 40)
                    }
                }
            }

            Section("オプション") {
                Toggle("マウスカーソルを含める", isOn: $showCursor)
                Toggle("キャプチャ時にサウンドを再生", isOn: $playSound)
            }
        }
        .padding()
        .onAppear {
            updateDisplayPath()
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

                HStack {
                    Text("ウィンドウキャプチャ")
                    Spacer()
                    Text("⌘⇧5")
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

            Text("バージョン 1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("まるでマスですくうように\n簡単に正確にスクリーンショットを作成します")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()

            Text("© 2025")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
