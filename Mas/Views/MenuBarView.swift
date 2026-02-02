import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: CaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            captureFrameButton
            captureModeButtons
            windowListSection
            openWindowsSection
            bottomSection
        }
        .frame(width: 250)
        .onAppear {
            viewModel.cleanupClosedWindows()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Text("Mas")
                .font(.headline)
            Spacer()
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        Divider()
    }

    @ViewBuilder
    private var captureFrameButton: some View {
        Button(action: { showCaptureFrame() }) {
            HStack {
                Image(systemName: "rectangle.dashed")
                    .frame(width: 20)
                Text("キャプチャ枠を表示")
                Spacer()
                Text("⌘⇧6")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .buttonStyle(NoHighlightButtonStyle())
        .padding(.horizontal)
        .padding(.vertical, 4)
        Divider()
    }

    @ViewBuilder
    private var captureModeButtons: some View {
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
            .buttonStyle(NoHighlightButtonStyle())
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var windowListSection: some View {
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
                        .buttonStyle(NoHighlightButtonStyle())
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    @ViewBuilder
    private var openWindowsSection: some View {
        if !viewModel.editorWindows.isEmpty {
            Divider()
            HStack {
                Text("開いているウィンドウ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.editorWindows.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.editorWindows) { windowInfo in
                        HStack {
                            Button(action: { focusWindow(windowInfo) }) {
                                HStack {
                                    Image(systemName: windowInfo.screenshot.mode.icon)
                                        .frame(width: 16)
                                    Text(windowInfo.displayName)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(NoHighlightButtonStyle())

                            Button(action: { closeWindow(windowInfo) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(NoHighlightButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 120)

            Button(action: closeAllWindows) {
                HStack {
                    Image(systemName: "xmark.rectangle")
                        .frame(width: 20)
                    Text("すべて閉じる")
                    Spacer()
                }
            }
            .buttonStyle(NoHighlightButtonStyle())
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var bottomSection: some View {
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
        .buttonStyle(NoHighlightButtonStyle())
        .padding(.horizontal)
        .padding(.vertical, 4)

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
        .buttonStyle(NoHighlightButtonStyle())
        .padding(.horizontal)
        .padding(.vertical, 4)

        Spacer()
            .frame(height: 8)
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

    private func showCaptureFrame() {
        dismissMenu()
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await viewModel.showCaptureFrame()
        }
    }

    private func focusWindow(_ windowInfo: CaptureViewModel.EditorWindowInfo) {
        dismissMenu()
        windowInfo.windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow(_ windowInfo: CaptureViewModel.EditorWindowInfo) {
        viewModel.closeEditorWindow(windowInfo)
    }

    private func closeAllWindows() {
        dismissMenu()
        viewModel.closeAllEditorWindows()
    }
}
