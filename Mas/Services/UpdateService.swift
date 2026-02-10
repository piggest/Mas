import Foundation
import AppKit

enum UpdateStatus: Equatable {
    case idle
    case checking
    case available(version: String)
    case downloading(progress: Double)
    case installing
    case readyToRestart
    case upToDate
    case error(String)
}

@MainActor
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var status: UpdateStatus = .idle

    private let repoOwner = "piggest"
    private let repoName = "Mas"
    private var periodicTask: Task<Void, Never>?
    private var latestDownloadURL: URL?

    private init() {}

    // MARK: - Public

    func checkForUpdate() async {
        status = .checking
        do {
            guard let release = try await fetchLatestRelease() else {
                status = .upToDate
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            if isNewer(release.tagName, than: currentVersion) {
                latestDownloadURL = release.dmgURL
                status = .available(version: release.tagName)
            } else {
                status = .upToDate
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func downloadAndInstall() async {
        guard let dmgURL = latestDownloadURL else {
            status = .error("ダウンロードURLが見つかりません")
            return
        }

        do {
            // ダウンロード
            status = .downloading(progress: 0)
            let localURL = try await downloadDMG(from: dmgURL)

            // インストール
            status = .installing
            try await installFromDMG(at: localURL)

            // クリーンアップ
            try? FileManager.default.removeItem(at: localURL)

            status = .readyToRestart
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func restart() {
        let appPath = "/Applications/Mas.app"
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", "sleep 1 && open \"\(appPath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    func startPeriodicCheck() {
        periodicTask?.cancel()
        periodicTask = Task {
            // 起動30秒後に初回チェック
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled { return }
            await checkForUpdate()

            // 以降4時間ごと
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4 * 60 * 60 * 1_000_000_000)
                if Task.isCancelled { return }
                let enabled = UserDefaults.standard.bool(forKey: "autoUpdateEnabled")
                if enabled {
                    await checkForUpdate()
                }
            }
        }
    }

    func stopPeriodicCheck() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    // MARK: - Private

    private struct ReleaseInfo {
        let tagName: String
        let dmgURL: URL
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo? {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            return nil
        }

        // DMGアセットを探す
        let dmgAsset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.lowercased().hasSuffix(".dmg")
        }

        guard let dmgAsset = dmgAsset,
              let downloadURLString = dmgAsset["browser_download_url"] as? String,
              let dmgURL = URL(string: downloadURLString) else {
            return nil
        }

        // "v" プレフィックスを除去
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return ReleaseInfo(tagName: version, dmgURL: dmgURL)
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private func downloadDMG(from url: URL) async throws -> URL {
        let (localURL, _) = try await URLSession.shared.download(from: url)

        // 一時ディレクトリにDMGとして保存
        let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("Mas-update.dmg")
        try? FileManager.default.removeItem(at: dmgPath)
        try FileManager.default.moveItem(at: localURL, to: dmgPath)

        await MainActor.run {
            status = .downloading(progress: 1.0)
        }

        return dmgPath
    }

    private func installFromDMG(at dmgPath: URL) async throws {
        let mountPoint = try await mountDMG(at: dmgPath)
        defer {
            Task.detached {
                await self.unmountDMG(at: mountPoint)
            }
        }

        // マウントされたDMG内のMas.appを探す
        let appSource = mountPoint.appendingPathComponent("Mas.app")
        guard FileManager.default.fileExists(atPath: appSource.path) else {
            throw UpdateError.appNotFoundInDMG
        }

        let appDest = URL(fileURLWithPath: "/Applications/Mas.app")
        let backupDest = URL(fileURLWithPath: "/Applications/Mas.app.bak")

        // バックアップ→置換→バックアップ削除
        try? FileManager.default.removeItem(at: backupDest)

        if FileManager.default.fileExists(atPath: appDest.path) {
            try FileManager.default.moveItem(at: appDest, to: backupDest)
        }

        do {
            try FileManager.default.copyItem(at: appSource, to: appDest)
            // 成功したらバックアップ削除
            try? FileManager.default.removeItem(at: backupDest)
        } catch {
            // 失敗したらバックアップを復元
            try? FileManager.default.moveItem(at: backupDest, to: appDest)
            throw error
        }
    }

    private func mountDMG(at path: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.launchPath = "/usr/bin/hdiutil"
                process.arguments = ["attach", path.path, "-nobrowse", "-quiet", "-mountrandom", "/tmp"]

                let pipe = Pipe()
                process.standardOutput = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        // hdiutil出力の最後の行からマウントポイントを取得
                        let lines = output.components(separatedBy: "\n")
                        if let lastLine = lines.last(where: { !$0.isEmpty }),
                           let mountPoint = lastLine.components(separatedBy: "\t").last?.trimmingCharacters(in: .whitespaces) {
                            continuation.resume(returning: URL(fileURLWithPath: mountPoint))
                        } else {
                            continuation.resume(throwing: UpdateError.mountFailed)
                        }
                    } else {
                        continuation.resume(throwing: UpdateError.mountFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func unmountDMG(at mountPoint: URL) {
        let process = Process()
        process.launchPath = "/usr/bin/hdiutil"
        process.arguments = ["detach", mountPoint.path, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }
}

enum UpdateError: LocalizedError {
    case mountFailed
    case appNotFoundInDMG

    var errorDescription: String? {
        switch self {
        case .mountFailed:
            return "DMGのマウントに失敗しました"
        case .appNotFoundInDMG:
            return "DMG内にMas.appが見つかりません"
        }
    }
}
