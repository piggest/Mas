import AppKit
import CoreGraphics

@MainActor
class ScreenCaptureService: NSObject {

    // MARK: - Full Screen Capture

    func captureFullScreen() async throws -> CGImage {
        guard let screen = NSScreen.main else {
            throw CaptureError.noDisplayFound
        }

        // 自アプリのウィンドウを除外してキャプチャ
        let screenRect = screen.frame
        guard let image = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.captureFailedWithError("CGWindowListCreateImage failed")
        }

        // 自アプリのウィンドウIDを取得
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myWindowIDs: Set<CGWindowID> = {
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
            var ids = Set<CGWindowID>()
            for info in list {
                if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == myPID,
                   let wid = info[kCGWindowNumber as String] as? CGWindowID {
                    ids.insert(wid)
                }
            }
            return ids
        }()

        // 自アプリのウィンドウがなければそのまま返す
        if myWindowIDs.isEmpty {
            return image
        }

        // 自アプリのウィンドウを除外して再キャプチャ
        // optionOnScreenAboveWindow で自アプリの最下層ウィンドウの下のウィンドウのみ取得
        // → excludeDesktopElements で自アプリを除外
        guard let filteredImage = CGWindowListCreateImage(
            screenRect,
            .optionAll,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) else {
            return image
        }

        // 自アプリを除外するには、ウィンドウIDリストを指定してキャプチャ
        // CGWindowListCreateImageFromArray を使用
        guard let allWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return image
        }

        var otherWindowIDs: [CGWindowID] = []
        for info in allWindows {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if !myWindowIDs.contains(wid) {
                otherWindowIDs.append(wid)
            }
        }

        guard !otherWindowIDs.isEmpty else { return image }

        let windowArray = otherWindowIDs as CFArray
        guard let excludedImage = CGImage(windowListFromArrayScreenBounds: screenRect,
                                          windowArray: windowArray as CFArray,
                                          imageOption: [.bestResolution]) else {
            return image
        }

        return excludedImage
    }

    // MARK: - Region Capture

    func captureRegion(_ region: CGRect) async throws -> CGImage {
        let fullImage = try await captureFullScreen()

        guard let screen = NSScreen.main else {
            throw CaptureError.noDisplayFound
        }

        let scale = CGFloat(fullImage.width) / screen.frame.width
        let scaledRect = CGRect(
            x: region.origin.x * scale,
            y: region.origin.y * scale,
            width: region.width * scale,
            height: region.height * scale
        )

        guard let croppedImage = fullImage.cropping(to: scaledRect) else {
            throw CaptureError.captureFailedWithError("Failed to crop image")
        }

        return croppedImage
    }

    // MARK: - Window Capture

    struct WindowInfo: Identifiable {
        let id: CGWindowID
        let name: String
        let ownerName: String
        let bounds: CGRect
    }

    func getAvailableWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [WindowInfo] = []

        for windowInfo in windowList {
            guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                continue
            }

            // 小さすぎるウィンドウは除外
            guard width > 50 && height > 50 else { continue }

            let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
            let bounds = CGRect(x: x, y: y, width: width, height: height)

            // 自分自身のアプリは除外
            if ownerName == "Mas" { continue }

            let info = WindowInfo(
                id: windowID,
                name: windowName,
                ownerName: ownerName,
                bounds: bounds
            )
            windows.append(info)
        }

        return windows
    }

    func captureWindow(windowID: CGWindowID) async throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureError.captureFailedWithError("Window capture failed")
        }

        return image
    }

    // MARK: - Helper

    private func loadImage(from path: String) -> CGImage? {
        guard let dataProvider = CGDataProvider(filename: path) else { return nil }
        return CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

enum CaptureError: Error, LocalizedError {
    case noDisplayFound
    case noWindowSelected
    case captureFailedWithError(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "ディスプレイが見つかりません"
        case .noWindowSelected:
            return "ウィンドウが選択されていません"
        case .captureFailedWithError(let message):
            return "キャプチャに失敗しました: \(message)"
        }
    }
}
