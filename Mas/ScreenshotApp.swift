import SwiftUI

@main
struct ScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var captureViewModel = CaptureViewModel()

    var body: some Scene {
        MenuBarExtra("Mas", image: "MenuBarIcon") {
            MenuBarView()
                .environmentObject(captureViewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindow()
        }
    }
}
