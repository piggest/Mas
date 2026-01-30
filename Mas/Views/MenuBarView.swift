import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: CaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mas")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider()

            ForEach(CaptureMode.allCases) { mode in
                Button(action: { performCapture(mode: mode) }) {
                    HStack {
                        Image(systemName: mode.icon)
                            .frame(width: 20)
                        Text(mode.rawValue)
                        Spacer()
                        Text(mode.shortcut)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if !viewModel.availableWindows.isEmpty {
                Divider()
                Text("ウィンドウ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.availableWindows) { window in
                            Button(action: { captureWindow(window) }) {
                                HStack {
                                    Text(window.ownerName)
                                        .lineLimit(1)
                                    if !window.name.isEmpty {
                                        Text("- \(window.name)")
                                            .lineLimit(1)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Divider()

            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                        .frame(width: 20)
                    Text("設定...")
                    Spacer()
                    Text("⌘,")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                        .frame(width: 20)
                    Text("終了")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .keyboardShortcut("q", modifiers: .command)

            Spacer()
                .frame(height: 8)
        }
        .frame(width: 250)
    }

    private func dismissMenu() {
        // MenuBarExtraのパネルを閉じる
        for window in NSApp.windows {
            // NSPanelでlevelがpopUpMenu付近のものを探す
            if window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue - 1 &&
               window.level.rawValue <= NSWindow.Level.popUpMenu.rawValue + 1 {
                window.orderOut(nil)
                break
            }
        }
    }

    private func performCapture(mode: CaptureMode) {
        if mode != .window {
            dismissMenu()
        }
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            switch mode {
            case .fullScreen:
                await viewModel.captureFullScreen()
            case .region:
                await viewModel.startRegionSelection()
            case .window:
                await viewModel.loadAvailableWindows()
            }
        }
    }

    private func captureWindow(_ window: ScreenCaptureService.WindowInfo) {
        dismissMenu()
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await viewModel.captureWindow(window)
        }
    }

    private func openSettings() {
        dismissMenu()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
