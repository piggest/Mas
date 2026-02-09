import AppKit
import CoreGraphics

// MARK: - NSScreen マルチスクリーン対応ヘルパー

extension NSScreen {
    /// プライマリスクリーンの高さ（CG⇔NS座標変換のベース）
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens[0].frame.height
    }

    /// このスクリーンのCG座標系（左上原点）でのフレーム
    var cgFrame: CGRect {
        let primaryHeight = NSScreen.primaryScreenHeight
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// CGDirectDisplayID を取得
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// CG座標の矩形を含むスクリーンを検索（最も重なりが大きいスクリーンを返す）
    static func screenContaining(cgRect: CGRect) -> NSScreen? {
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.cgFrame.intersection(cgRect)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestScreen = screen
                }
            }
        }
        return bestScreen ?? NSScreen.main
    }

    /// CG座標の矩形をNS座標（左下原点）に変換
    static func cgToNS(_ cgRect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.primaryScreenHeight
        return NSRect(
            x: cgRect.origin.x,
            y: primaryHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}

@MainActor
class ScreenCaptureService: NSObject {

    // MARK: - 指定スクリーンのキャプチャ

    func captureScreen(_ screen: NSScreen) async throws -> CGImage {
        let cgRect = screen.cgFrame
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let allWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.captureFailedWithError("Failed to get window list")
        }

        var otherWindowIDs: [NSNumber] = []
        for info in allWindows {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if pid != myPID {
                otherWindowIDs.append(NSNumber(value: wid))
            }
        }

        if !otherWindowIDs.isEmpty {
            let windowArray = otherWindowIDs as CFArray
            if let image = CGImage(windowListFromArrayScreenBounds: cgRect,
                                   windowArray: windowArray,
                                   imageOption: [.bestResolution]) {
                return image
            }
        }

        // フォールバック: ディスプレイIDから直接キャプチャ
        guard let displayID = screen.displayID else {
            throw CaptureError.noDisplayFound
        }
        guard let image = CGDisplayCreateImage(displayID) else {
            throw CaptureError.captureFailedWithError("CGDisplayCreateImage failed")
        }
        return image
    }

    // MARK: - 全スクリーンをキャプチャ

    func captureAllScreens() async throws -> [CGDirectDisplayID: CGImage] {
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let allWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.captureFailedWithError("Failed to get window list")
        }

        var otherWindowIDs: [NSNumber] = []
        for info in allWindows {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if pid != myPID {
                otherWindowIDs.append(NSNumber(value: wid))
            }
        }

        var result: [CGDirectDisplayID: CGImage] = [:]
        let windowArray = otherWindowIDs as CFArray

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let cgRect = screen.cgFrame

            if !otherWindowIDs.isEmpty {
                if let image = CGImage(windowListFromArrayScreenBounds: cgRect,
                                       windowArray: windowArray,
                                       imageOption: [.bestResolution]) {
                    result[displayID] = image
                    continue
                }
            }

            // フォールバック
            if let image = CGDisplayCreateImage(displayID) {
                result[displayID] = image
            }
        }

        return result
    }

    // MARK: - Full Screen Capture（後方互換）

    func captureFullScreen() async throws -> CGImage {
        guard let screen = NSScreen.main else {
            throw CaptureError.noDisplayFound
        }
        return try await captureScreen(screen)
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
