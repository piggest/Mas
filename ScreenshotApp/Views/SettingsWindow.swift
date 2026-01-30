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

    var body: some View {
        Form {
            Section {
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

            Section {
                Toggle("マウスカーソルを含める", isOn: $showCursor)
                Toggle("キャプチャ時にサウンドを再生", isOn: $playSound)
            }
        }
        .padding()
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
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Screenshot App")
                .font(.title)
                .fontWeight(.bold)

            Text("バージョン 1.0")
                .foregroundColor(.secondary)

            Text("macOS用のシンプルなスクリーンショットアプリ")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Text("© 2024")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
