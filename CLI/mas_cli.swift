import Foundation
import AppKit
import Vision
import ImageIO
import CoreGraphics

// MARK: - Constants

let appVersion = "1.7.3"
let bundleIdentifier = "com.example.Mas"

let historyFileURL: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Mas/history.json")
}()

let settingsKeys: [(key: String, description: String, type: String)] = [
    ("developerMode", "開発者モード", "Bool"),
    ("defaultFormat", "保存形式 (PNG/JPEG)", "String"),
    ("jpegQuality", "JPEG品質 (0.1-1.0)", "Double"),
    ("showCursor", "マウスカーソルを含める", "Bool"),
    ("playSound", "キャプチャ時にサウンド再生", "Bool"),
    ("autoSaveEnabled", "ファイルに保存", "Bool"),
    ("autoSaveFolder", "保存先フォルダ", "String"),
    ("autoCopyToClipboard", "クリップボードにコピー", "Bool"),
    ("closeOnDragSuccess", "ドラッグ成功時に閉じる", "Bool"),
    ("pinBehavior", "ピン動作 (alwaysOn/latestOnly/off)", "String"),
]

// MARK: - History Model

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let mode: String
    let filePath: String
    let width: Int
    let height: Int
    let windowX: Double?
    let windowY: Double?
    let windowW: Double?
    let windowH: Double?
    var baseFilePath: String?
    var hasAnnotations: Bool?
    var isFavorite: Bool?

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Utility

func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
}

func isAppRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
}

func ensureAppRunning() {
    guard !isAppRunning() else { return }
    print("Mas.app を起動中...")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Mas", "--background"]
    try? process.run()
    process.waitUntilExit()
    Thread.sleep(forTimeInterval: 1.5)
    guard isAppRunning() else {
        printError("Mas.app の起動に失敗しました")
        exit(1)
    }
}

func sendNotification(_ name: String, object: String? = nil) {
    ensureAppRunning()
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name(name),
        object: object,
        userInfo: nil,
        deliverImmediately: true
    )
}

// MARK: - Commands

func parseDelay(from args: [String]) -> Int? {
    if let idx = args.firstIndex(of: "--delay"),
       idx + 1 < args.count,
       let sec = Int(args[idx + 1]), sec > 0 {
        return sec
    }
    return nil
}

func parseOutput(from args: [String]) -> String? {
    if let idx = args.firstIndex(of: "--output"),
       idx + 1 < args.count {
        return (args[idx + 1] as NSString).expandingTildeInPath
    }
    return nil
}

func countdown(seconds: Int, label: String) {
    for i in stride(from: seconds, through: 1, by: -1) {
        print("\r\(i)秒後に\(label)...", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1.0)
    }
    print("\rキャプチャ！              ")
}

func screencapture(to outputPath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", outputPath]
    try? process.run()
    process.waitUntilExit()
}

struct MasWindow {
    let id: CGWindowID
    let title: String
    let width: Int
    let height: Int
}

func findMasWindows() -> [MasWindow] {
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return windowList.compactMap { info in
        guard let ownerName = info[kCGWindowOwnerName as String] as? String,
              ownerName == "Mas",
              let windowID = info[kCGWindowNumber as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? CGFloat, width > 30,
              let height = bounds["Height"] as? CGFloat, height > 30 else { return nil }
        let title = (info[kCGWindowName as String] as? String) ?? ""
        return MasWindow(id: CGWindowID(windowID), title: title, width: Int(width), height: Int(height))
    }
}

func captureWindow(windowID: CGWindowID, to outputPath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(windowID), outputPath]
    try? process.run()
    process.waitUntilExit()
}

func captureWindowByTitle(containing keyword: String, to outputPath: String) -> Bool {
    let windows = findMasWindows()
    if let win = windows.first(where: { $0.title.contains(keyword) }) {
        captureWindow(windowID: win.id, to: outputPath)
        return true
    }
    // キーワードにマッチしなければ最大のウィンドウを使用
    if let win = windows.max(by: { $0.width * $0.height < $1.width * $1.height }) {
        captureWindow(windowID: win.id, to: outputPath)
        return true
    }
    return false
}

func defaultOutputPath(prefix: String) -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = dateFormatter.string(from: Date())
    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    return desktop.appendingPathComponent("mas-\(prefix)-\(timestamp).png").path
}

func handleCapture(_ args: [String]) {
    guard let subcommand = args.first else {
        printError("Usage: mas-cli capture <fullscreen|region|frame|menu|library> [--delay N] [--output path]")
        exit(1)
    }

    let restArgs = Array(args.dropFirst())
    let delay = parseDelay(from: restArgs)

    switch subcommand {
    case "fullscreen", "region", "frame":
        let notificationName: String
        let label: String
        switch subcommand {
        case "fullscreen":
            notificationName = "com.example.Mas.capture.fullscreen"
            label = "全画面キャプチャ"
        case "region":
            notificationName = "com.example.Mas.capture.region"
            label = "範囲選択キャプチャ"
        default:
            notificationName = "com.example.Mas.capture.frame"
            label = "キャプチャ枠表示"
        }

        if let delay = delay {
            ensureAppRunning()
            countdown(seconds: delay, label: label)
            sendNotification(notificationName)
        } else {
            sendNotification(notificationName)
            print("\(label) コマンドを送信しました")
        }

    case "menu":
        let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "menu")
        let wait = delay ?? 1
        ensureAppRunning()
        sendNotification("com.example.Mas.show.menu")
        Thread.sleep(forTimeInterval: Double(wait))
        // ポップオーバーウィンドウ（タイトルなし、適切なサイズ）をキャプチャ
        let menuWindows = findMasWindows().filter { $0.title.isEmpty && $0.width > 100 && $0.height > 100 }
        if let win = menuWindows.first {
            captureWindow(windowID: win.id, to: output)
        } else {
            screencapture(to: output)
        }
        print("保存しました: \(output)")

    case "library":
        let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "library")
        let wait = delay ?? 1
        ensureAppRunning()
        sendNotification("com.example.Mas.show.library")
        Thread.sleep(forTimeInterval: Double(wait))
        if !captureWindowByTitle(containing: "ライブラリ", to: output) {
            screencapture(to: output)
        }
        print("保存しました: \(output)")

    case "settings":
        let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "settings")
        let wait = delay ?? 1
        ensureAppRunning()
        sendNotification("com.example.Mas.show.settings")
        Thread.sleep(forTimeInterval: Double(wait))
        if !captureWindowByTitle(containing: "設定", to: output) {
            screencapture(to: output)
        }
        print("保存しました: \(output)")

    case "editor":
        let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "editor")
        Thread.sleep(forTimeInterval: Double(delay ?? 1))
        // エディタウィンドウ（最大のMasウィンドウ）をキャプチャ
        let windows = findMasWindows().filter { $0.width > 200 && $0.height > 200 }
        if let win = windows.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            captureWindow(windowID: win.id, to: output)
            print("保存しました: \(output)")
        } else {
            printError("エディタウィンドウが見つかりません")
            exit(1)
        }

    case "window":
        // ウィンドウ一覧表示 or 指定IDキャプチャ
        if let idStr = restArgs.first, let wid = UInt32(idStr) {
            let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "window")
            captureWindow(windowID: CGWindowID(wid), to: output)
            print("保存しました: \(output)")
        } else {
            let windows = findMasWindows()
            if windows.isEmpty {
                print("Masのウィンドウが見つかりません")
            } else {
                print("Mas ウィンドウ一覧:")
                for win in windows {
                    print("  ID: \(win.id)  \(win.width)x\(win.height)  \"\(win.title)\"")
                }
            }
        }

    case "delayed":
        let output = parseOutput(from: restArgs) ?? defaultOutputPath(prefix: "delayed")
        let wait = delay ?? 5
        countdown(seconds: wait, label: "キャプチャ")
        screencapture(to: output)
        print("保存しました: \(output)")

    default:
        printError("Unknown capture mode: \(subcommand)")
        printError("Available: fullscreen, region, frame, menu, library, settings, editor, window, delayed")
        exit(1)
    }
}

func handleOCR(_ args: [String]) {
    guard let imagePath = args.first else {
        printError("Usage: mas-cli ocr <image-path> [--json]")
        exit(1)
    }
    let jsonOutput = args.contains("--json")
    let absPath = (imagePath as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: absPath)

    guard FileManager.default.fileExists(atPath: absPath) else {
        printError("ファイルが見つかりません: \(imagePath)")
        exit(1)
    }

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        printError("画像の読み込みに失敗しました: \(imagePath)")
        exit(1)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var recognizedTexts: [(text: String, x: Double, y: Double, w: Double, h: Double)] = []

    let request = VNRecognizeTextRequest { request, error in
        defer { semaphore.signal() }
        if let error = error {
            printError("OCRエラー: \(error.localizedDescription)")
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

        let imageWidth = Double(cgImage.width)
        let imageHeight = Double(cgImage.height)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            recognizedTexts.append((
                text: candidate.string,
                x: box.origin.x * imageWidth,
                y: box.origin.y * imageHeight,
                w: box.width * imageWidth,
                h: box.height * imageHeight
            ))
        }
    }
    request.recognitionLanguages = ["ja", "en"]
    request.recognitionLevel = .accurate

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        printError("OCR実行エラー: \(error.localizedDescription)")
        exit(1)
    }
    semaphore.wait()

    if recognizedTexts.isEmpty {
        print("テキストが検出されませんでした")
        return
    }

    if jsonOutput {
        let jsonArray = recognizedTexts.map { item -> [String: Any] in
            [
                "text": item.text,
                "rect": ["x": item.x, "y": item.y, "width": item.w, "height": item.h]
            ]
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        for item in recognizedTexts {
            print(item.text)
        }
    }
}

func handleHistory(_ args: [String]) {
    guard let subcommand = args.first else {
        printError("Usage: mas-cli history <list|delete> [options]")
        exit(1)
    }

    switch subcommand {
    case "list":
        historyList(Array(args.dropFirst()))
    case "delete":
        historyDelete(Array(args.dropFirst()))
    default:
        printError("Unknown history command: \(subcommand)")
        printError("Available: list, delete")
        exit(1)
    }
}

func loadHistory() -> [HistoryEntry] {
    guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return [] }
    guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
}

func saveHistory(_ entries: [HistoryEntry]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted
    guard let data = try? encoder.encode(entries) else { return }
    try? data.write(to: historyFileURL, options: .atomic)
}

func historyList(_ args: [String]) {
    let favoritesOnly = args.contains("--favorites")
    let jsonOutput = args.contains("--json")

    var entries = loadHistory()
    if favoritesOnly {
        entries = entries.filter { $0.isFavorite == true }
    }

    if entries.isEmpty {
        print(favoritesOnly ? "お気に入りはありません" : "履歴はありません")
        return
    }

    if jsonOutput {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
        return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    for entry in entries {
        let star = entry.isFavorite == true ? " *" : ""
        let exists = entry.fileExists ? "" : " [missing]"
        let annotations = entry.hasAnnotations == true ? " [annotated]" : ""
        print("\(entry.id.uuidString.prefix(8))  \(dateFormatter.string(from: entry.timestamp))  \(entry.mode)  \(entry.width)x\(entry.height)\(star)\(annotations)\(exists)")
        print("  \(entry.fileName)")
    }
    print("\n合計: \(entries.count) 件")
}

func historyDelete(_ args: [String]) {
    guard let idPrefix = args.first else {
        printError("Usage: mas-cli history delete <id>")
        exit(1)
    }

    var entries = loadHistory()
    let matching = entries.filter { $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased()) }

    if matching.isEmpty {
        printError("一致するエントリが見つかりません: \(idPrefix)")
        exit(1)
    }
    if matching.count > 1 {
        printError("複数のエントリが一致します。もう少し長いIDを指定してください")
        for entry in matching {
            print("  \(entry.id.uuidString)")
        }
        exit(1)
    }

    let target = matching[0]
    entries.removeAll { $0.id == target.id }
    saveHistory(entries)
    print("削除しました: \(target.fileName) (\(target.id.uuidString.prefix(8)))")
}

func handleSettings(_ args: [String]) {
    guard let subcommand = args.first else {
        printError("Usage: mas-cli settings <list|get|set>")
        exit(1)
    }

    switch subcommand {
    case "list":
        settingsList()
    case "get":
        settingsGet(Array(args.dropFirst()))
    case "set":
        settingsSet(Array(args.dropFirst()))
    default:
        printError("Unknown settings command: \(subcommand)")
        printError("Available: list, get, set")
        exit(1)
    }
}

func settingsList() {
    let defaults = UserDefaults(suiteName: bundleIdentifier)
    for setting in settingsKeys {
        let value = defaults?.object(forKey: setting.key)
        let valueStr = value.map { "\($0)" } ?? "(未設定)"
        print("\(setting.key): \(valueStr)  — \(setting.description)")
    }
}

func settingsGet(_ args: [String]) {
    guard let key = args.first else {
        printError("Usage: mas-cli settings get <key>")
        exit(1)
    }

    guard settingsKeys.contains(where: { $0.key == key }) else {
        printError("未知の設定キー: \(key)")
        printError("利用可能なキー: \(settingsKeys.map { $0.key }.joined(separator: ", "))")
        exit(1)
    }

    let defaults = UserDefaults(suiteName: bundleIdentifier)
    if let value = defaults?.object(forKey: key) {
        print("\(value)")
    } else {
        print("(未設定)")
    }
}

func settingsSet(_ args: [String]) {
    guard args.count >= 2 else {
        printError("Usage: mas-cli settings set <key> <value>")
        exit(1)
    }

    let key = args[0]
    let valueStr = args[1]

    guard let setting = settingsKeys.first(where: { $0.key == key }) else {
        printError("未知の設定キー: \(key)")
        printError("利用可能なキー: \(settingsKeys.map { $0.key }.joined(separator: ", "))")
        exit(1)
    }

    let defaults = UserDefaults(suiteName: bundleIdentifier)

    switch setting.type {
    case "Bool":
        guard let boolValue = Bool(valueStr) else {
            printError("Bool値を指定してください: true / false")
            exit(1)
        }
        defaults?.set(boolValue, forKey: key)
    case "Double":
        guard let doubleValue = Double(valueStr) else {
            printError("数値を指定してください")
            exit(1)
        }
        defaults?.set(doubleValue, forKey: key)
    case "String":
        defaults?.set(valueStr, forKey: key)
    default:
        defaults?.set(valueStr, forKey: key)
    }

    print("設定しました: \(key) = \(valueStr)")
}

func handleOpen(_ args: [String]) {
    guard let filePath = args.first else {
        printError("Usage: mas-cli open <file-path>")
        exit(1)
    }

    let absPath = (filePath as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: absPath) else {
        printError("ファイルが見つかりません: \(filePath)")
        exit(1)
    }

    sendNotification("com.example.Mas.open.file", object: absPath)
    print("Mas エディタで開きます: \(URL(fileURLWithPath: absPath).lastPathComponent)")
}

func printVersion() {
    print("mas-cli version \(appVersion)")
}

func printAppStatus() {
    if isAppRunning() {
        print("Mas.app: 起動中")
    } else {
        print("Mas.app: 停止中")
    }
}

func printUsage() {
    print("""
    mas-cli — Mas コマンドラインツール

    Usage: mas-cli <command> [options]

    Commands:
      capture fullscreen|region|frame [--delay N]  キャプチャを実行
      capture menu [--delay N] [--output path]     メニューを開いてキャプチャ
      capture library [--delay N] [--output path]  ライブラリを開いてキャプチャ
      capture delayed [--delay N] [--output path]  遅延キャプチャ（右クリックメニュー等）
      annotate <image> <type> [options]  画像にアノテーションを追加
      ocr <image-path> [--json]         画像からテキストを認識
      history list [--favorites] [--json] 履歴を一覧表示
      history delete <id>               履歴を削除
      settings list                     設定を一覧表示
      settings get <key>                設定値を取得
      settings set <key> <value>        設定値を変更
      open <file-path>                  画像をエディタで開く
      version                           バージョンを表示
      status                            アプリの起動状態を確認
    """)
}

// MARK: - Annotate Command

func parseColorName(_ name: String) -> NSColor {
    switch name.lowercased() {
    case "red":     return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
    case "blue":    return NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    case "green":   return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
    case "yellow":  return NSColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
    case "orange":  return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
    case "white":   return .white
    case "black":   return .black
    case "purple":  return NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
    default:
        // #RRGGBB hex
        if name.hasPrefix("#"), name.count == 7 {
            let hex = String(name.dropFirst())
            if let val = UInt64(hex, radix: 16) {
                return NSColor(
                    red: CGFloat((val >> 16) & 0xFF) / 255.0,
                    green: CGFloat((val >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(val & 0xFF) / 255.0,
                    alpha: 1.0
                )
            }
        }
        return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0) // default: red
    }
}

func parseAnnotateColor(from args: [String]) -> NSColor {
    if let idx = args.firstIndex(of: "--color"), idx + 1 < args.count {
        return parseColorName(args[idx + 1])
    }
    return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0) // default: red
}

func parseAnnotateWidth(from args: [String], defaultValue: CGFloat = 3) -> CGFloat {
    if let idx = args.firstIndex(of: "--width"), idx + 1 < args.count, let w = Double(args[idx + 1]) {
        return CGFloat(w)
    }
    return defaultValue
}

func parseRect(from args: [String]) -> CGRect? {
    if let idx = args.firstIndex(of: "--rect"), idx + 1 < args.count {
        let parts = args[idx + 1].split(separator: ",").compactMap { Double($0) }
        if parts.count == 4 {
            return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
    }
    return nil
}

func parsePoint(from args: [String], flag: String) -> CGPoint? {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
        let parts = args[idx + 1].split(separator: ",").compactMap { Double($0) }
        if parts.count == 2 {
            return CGPoint(x: parts[0], y: parts[1])
        }
    }
    return nil
}

func loadImage(at path: String) -> NSImage {
    let absPath = (path as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: absPath),
          let image = NSImage(contentsOfFile: absPath) else {
        printError("画像の読み込みに失敗: \(path)")
        exit(1)
    }
    return image
}

func saveAnnotatedImage(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        printError("画像の変換に失敗しました")
        exit(1)
    }

    let ext = (path as NSString).pathExtension.lowercased()
    let data: Data?
    switch ext {
    case "jpg", "jpeg":
        data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    default:
        data = bitmap.representation(using: .png, properties: [:])
    }

    guard let imageData = data else {
        printError("画像のエンコードに失敗しました")
        exit(1)
    }

    do {
        try imageData.write(to: URL(fileURLWithPath: path))
    } catch {
        printError("ファイルの書き込みに失敗: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Annotation Drawing

func drawArrowOnImage(_ image: NSImage, start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat, stroke: Bool) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))

    let angle = atan2(end.y - start.y, end.x - start.x)
    let headLength: CGFloat = lineWidth * 7
    let headWidth: CGFloat = lineWidth * 2.5
    let tailWidth: CGFloat = lineWidth * 0.3
    let shaftEndWidth: CGFloat = lineWidth * 1.2

    let headBase = CGPoint(
        x: end.x - headLength * cos(angle),
        y: end.y - headLength * sin(angle)
    )

    let path = NSBezierPath()
    let perpAngle = angle + .pi / 2

    let tailLeft = CGPoint(x: start.x + tailWidth * cos(perpAngle), y: start.y + tailWidth * sin(perpAngle))
    let tailRight = CGPoint(x: start.x - tailWidth * cos(perpAngle), y: start.y - tailWidth * sin(perpAngle))
    let shaftEnd1 = CGPoint(x: headBase.x + shaftEndWidth * cos(perpAngle), y: headBase.y + shaftEndWidth * sin(perpAngle))
    let shaftEnd2 = CGPoint(x: headBase.x - shaftEndWidth * cos(perpAngle), y: headBase.y - shaftEndWidth * sin(perpAngle))
    let headLeft = CGPoint(x: headBase.x + headWidth * cos(perpAngle), y: headBase.y + headWidth * sin(perpAngle))
    let headRight = CGPoint(x: headBase.x - headWidth * cos(perpAngle), y: headBase.y - headWidth * sin(perpAngle))

    path.move(to: tailLeft)
    path.line(to: shaftEnd1)
    path.line(to: headLeft)
    path.line(to: end)
    path.line(to: headRight)
    path.line(to: shaftEnd2)
    path.line(to: tailRight)
    path.close()

    color.setFill()
    path.fill()

    if stroke {
        NSColor.black.withAlphaComponent(0.3).setStroke()
        path.lineWidth = lineWidth * 0.8
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = lineWidth * 0.4
        path.stroke()
    }

    result.unlockFocus()
    return result
}

func drawRectOnImage(_ image: NSImage, rect: CGRect, color: NSColor, lineWidth: CGFloat, filled: Bool, stroke: Bool) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))

    let path = NSBezierPath(rect: rect)
    path.lineWidth = lineWidth

    if filled {
        color.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    if stroke {
        let outerPath = NSBezierPath(rect: rect)
        outerPath.lineWidth = lineWidth + 4
        NSColor.black.withAlphaComponent(0.3).setStroke()
        outerPath.stroke()
        let whitePath = NSBezierPath(rect: rect)
        whitePath.lineWidth = lineWidth + 2
        NSColor.white.setStroke()
        whitePath.stroke()
    }

    color.setStroke()
    path.stroke()

    result.unlockFocus()
    return result
}

func drawEllipseOnImage(_ image: NSImage, rect: CGRect, color: NSColor, lineWidth: CGFloat, filled: Bool, stroke: Bool) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))

    let path = NSBezierPath(ovalIn: rect)
    path.lineWidth = lineWidth

    if filled {
        color.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    if stroke {
        let outerPath = NSBezierPath(ovalIn: rect)
        outerPath.lineWidth = lineWidth + 4
        NSColor.black.withAlphaComponent(0.3).setStroke()
        outerPath.stroke()
        let whitePath = NSBezierPath(ovalIn: rect)
        whitePath.lineWidth = lineWidth + 2
        NSColor.white.setStroke()
        whitePath.stroke()
    }

    color.setStroke()
    path.stroke()

    result.unlockFocus()
    return result
}

func drawTextOnImage(_ image: NSImage, position: CGPoint, text: String, fontSize: CGFloat, color: NSColor, stroke: Bool) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))

    let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    let drawPosition = CGPoint(x: position.x, y: position.y - font.ascender)

    if stroke {
        let outerAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .strokeColor: NSColor.black.withAlphaComponent(0.5), .strokeWidth: 10.0
        ]
        NSAttributedString(string: text, attributes: outerAttrs).draw(at: drawPosition)

        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .strokeColor: NSColor.white, .strokeWidth: 6.0
        ]
        NSAttributedString(string: text, attributes: whiteAttrs).draw(at: drawPosition)

        let fillAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        NSAttributedString(string: text, attributes: fillAttrs).draw(at: drawPosition)
    } else {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        NSAttributedString(string: text, attributes: attrs).draw(at: drawPosition)
    }

    result.unlockFocus()
    return result
}

func drawHighlightOnImage(_ image: NSImage, rect: CGRect, color: NSColor) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))

    color.withAlphaComponent(0.4).setFill()
    NSBezierPath(rect: rect).fill()

    result.unlockFocus()
    return result
}

func drawMosaicOnImage(_ image: NSImage, rect: CGRect, pixelSize: Int) -> NSImage {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else {
        return image
    }

    let ciImage = CIImage(cgImage: cgImage)
    let croppedImage = ciImage.cropped(to: rect)

    guard let pixellateFilter = CIFilter(name: "CIPixellate") else { return image }
    pixellateFilter.setValue(croppedImage, forKey: kCIInputImageKey)
    pixellateFilter.setValue(NSNumber(value: pixelSize), forKey: kCIInputScaleKey)
    pixellateFilter.setValue(CIVector(x: rect.midX, y: rect.midY), forKey: kCIInputCenterKey)

    guard let pixellated = pixellateFilter.outputImage else { return image }
    let composited = pixellated.composited(over: ciImage)

    let context = CIContext()
    guard let outputCGImage = context.createCGImage(composited, from: ciImage.extent) else { return image }

    return NSImage(cgImage: outputCGImage, size: image.size)
}

func handleAnnotate(_ args: [String]) {
    guard args.count >= 2 else {
        printError("""
        Usage: mas-cli annotate <image> <type> [options]

        Types:
          arrow      --from x,y --to x,y [--color name] [--width N]
          rect       --rect x,y,w,h [--color name] [--width N] [--filled]
          ellipse    --rect x,y,w,h [--color name] [--width N] [--filled]
          text       --pos x,y --text "文字" [--size N] [--color name]
          highlight  --rect x,y,w,h [--color yellow]
          mosaic     --rect x,y,w,h [--pixel-size N]

        Options:
          --output path   出力先（省略時は元画像を上書き）
          --color name    色名 (red/blue/green/yellow/orange/white/black/purple/#RRGGBB)
          --width N       線の太さ (デフォルト: 3)
          --no-stroke     縁取りなし
        """)
        exit(1)
    }

    let imagePath = (args[0] as NSString).expandingTildeInPath
    let subcommand = args[1]
    let restArgs = Array(args.dropFirst(2))
    let outputPath = parseOutput(from: restArgs) ?? imagePath
    let color = parseAnnotateColor(from: restArgs)
    let lineWidth = parseAnnotateWidth(from: restArgs)
    let stroke = !restArgs.contains("--no-stroke")
    let filled = restArgs.contains("--filled")

    var image = loadImage(at: imagePath)

    switch subcommand {
    case "arrow":
        guard let from = parsePoint(from: restArgs, flag: "--from"),
              let to = parsePoint(from: restArgs, flag: "--to") else {
            printError("矢印には --from x,y --to x,y が必要です")
            exit(1)
        }
        image = drawArrowOnImage(image, start: from, end: to, color: color, lineWidth: lineWidth, stroke: stroke)

    case "rect":
        guard let rect = parseRect(from: restArgs) else {
            printError("四角には --rect x,y,w,h が必要です")
            exit(1)
        }
        image = drawRectOnImage(image, rect: rect, color: color, lineWidth: lineWidth, filled: filled, stroke: stroke)

    case "ellipse":
        guard let rect = parseRect(from: restArgs) else {
            printError("丸には --rect x,y,w,h が必要です")
            exit(1)
        }
        image = drawEllipseOnImage(image, rect: rect, color: color, lineWidth: lineWidth, filled: filled, stroke: stroke)

    case "text":
        guard let pos = parsePoint(from: restArgs, flag: "--pos") else {
            printError("テキストには --pos x,y が必要です")
            exit(1)
        }
        var textContent = "テキスト"
        if let idx = restArgs.firstIndex(of: "--text"), idx + 1 < restArgs.count {
            textContent = restArgs[idx + 1]
        }
        var fontSize: CGFloat = 16
        if let idx = restArgs.firstIndex(of: "--size"), idx + 1 < restArgs.count, let s = Double(restArgs[idx + 1]) {
            fontSize = CGFloat(s)
        }
        image = drawTextOnImage(image, position: pos, text: textContent, fontSize: fontSize, color: color, stroke: stroke)

    case "highlight":
        guard let rect = parseRect(from: restArgs) else {
            printError("ハイライトには --rect x,y,w,h が必要です")
            exit(1)
        }
        let highlightColor = restArgs.contains("--color") ? color : NSColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
        image = drawHighlightOnImage(image, rect: rect, color: highlightColor)

    case "mosaic":
        guard let rect = parseRect(from: restArgs) else {
            printError("モザイクには --rect x,y,w,h が必要です")
            exit(1)
        }
        var pixelSize = 10
        if let idx = restArgs.firstIndex(of: "--pixel-size"), idx + 1 < restArgs.count, let s = Int(restArgs[idx + 1]) {
            pixelSize = s
        }
        image = drawMosaicOnImage(image, rect: rect, pixelSize: pixelSize)

    default:
        printError("Unknown annotation type: \(subcommand)")
        printError("Available: arrow, rect, ellipse, text, highlight, mosaic")
        exit(1)
    }

    saveAnnotatedImage(image, to: outputPath)
    print("保存しました: \(outputPath)")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    printUsage()
    exit(0)
}

switch command {
case "capture":
    handleCapture(Array(args.dropFirst()))
case "annotate":
    handleAnnotate(Array(args.dropFirst()))
case "ocr":
    handleOCR(Array(args.dropFirst()))
case "history":
    handleHistory(Array(args.dropFirst()))
case "settings":
    handleSettings(Array(args.dropFirst()))
case "open":
    handleOpen(Array(args.dropFirst()))
case "version", "--version", "-v":
    printVersion()
case "status":
    printAppStatus()
case "help", "--help", "-h":
    printUsage()
default:
    printError("Unknown command: \(command)")
    printUsage()
    exit(1)
}
