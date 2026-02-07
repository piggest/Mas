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
        .onReceive(NotificationCenter.default.publisher(for: .windowPinChanged)) { _ in
            viewModel.objectWillChange.send()
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
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(NoHighlightButtonStyle())
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
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .buttonStyle(NoHighlightButtonStyle())
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
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(NoHighlightButtonStyle())
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
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.editorWindows) { windowInfo in
                        Button(action: { focusWindow(windowInfo) }) {
                            HStack(spacing: 8) {
                                Image(nsImage: windowInfo.screenshot.originalImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 36)
                                    .clipped()
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(windowInfo.displayName)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Button(action: {
                                            togglePin(windowInfo)
                                        }) {
                                            Image(systemName: windowInfo.windowController.window?.level == .floating ? "pin.fill" : "pin.slash")
                                                .font(.system(size: 8))
                                                .foregroundColor(windowInfo.windowController.window?.level == .floating ? .accentColor : .secondary)
                                        }
                                        .buttonStyle(NoHighlightButtonStyle())
                                    }
                                    let size = windowInfo.screenshot.originalImage.size
                                    Text("\(Int(size.width))×\(Int(size.height))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if let savedURL = windowInfo.screenshot.savedURL {
                                        Text(savedURL.lastPathComponent)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .onTapGesture {
                                                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                                            }
                                    }
                                }
                                Spacer()
                                Button(action: { closeWindow(windowInfo) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(NoHighlightButtonStyle())
                            }
                        }
                        .buttonStyle(NoHighlightButtonStyle())
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 180)

            Button(action: closeAllWindows) {
                HStack {
                    Image(systemName: "xmark.rectangle")
                        .frame(width: 20)
                    Text("すべて閉じる")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .buttonStyle(NoHighlightButtonStyle())
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
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(NoHighlightButtonStyle())

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
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .buttonStyle(NoHighlightButtonStyle())

        Spacer()
            .frame(height: 8)
    }

    private func dismissMenu() {
        // MenuBarExtraのパネルをアニメーションなしで即座に閉じる
        if let panel = NSApp.keyWindow as? NSPanel {
            panel.animationBehavior = .none
            panel.alphaValue = 0
            panel.orderOut(nil)
            // 次回表示時のためにalphaを復元
            panel.alphaValue = 1
        }
    }

    private func performCapture(mode: CaptureMode) {
        if mode != .window {
            dismissMenu()
        }
        Task {
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
            await viewModel.captureWindow(window)
        }
    }

    private func openSettings() {
        dismissMenu()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func quitApp() {
        guard !viewModel.isCapturing else { return }
        dismissMenu()
        NSApplication.shared.terminate(nil)
    }

    private func showCaptureFrame() {
        dismissMenu()
        Task {
            await viewModel.showCaptureFrame()
        }
    }

    private func togglePin(_ windowInfo: CaptureViewModel.EditorWindowInfo) {
        guard let window = windowInfo.windowController.window else { return }
        window.level = window.level == .floating ? .normal : .floating
        viewModel.objectWillChange.send()
        NotificationCenter.default.post(name: .windowPinChanged, object: window)
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
