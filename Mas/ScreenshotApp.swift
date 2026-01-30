import SwiftUI

@main
struct ScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var captureViewModel = CaptureViewModel()

    var body: some Scene {
        MenuBarExtra("Mas", systemImage: "camera.viewfinder") {
            MenuBarView()
                .environmentObject(captureViewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindow()
        }
    }
}
