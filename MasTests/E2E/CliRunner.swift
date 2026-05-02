import Foundation
import XCTest

/// `mas-cli` を Process 経由で起動して結果を返すテスト用ヘルパ。
///
/// ## 使い方
/// ```
/// let result = CliRunner.run("version")
/// XCTAssertEqual(result.exitCode, 0)
/// XCTAssertTrue(result.stdout.contains("mas-cli"))
/// ```
///
/// 初回呼び出し時に一度だけ `CLI/build.sh` を走らせて mas-cli バイナリを最新化する
/// （setUp 内で `CliRunner.ensureBuilt()` を呼ぶ）。
enum CliRunner {

    /// プロジェクトルート（リポジトリの直下）を `__FILE__` から推定する。
    /// `.../Mas/MasTests/E2E/CliRunner.swift` → `.../Mas`
    static let projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // E2E
            .deletingLastPathComponent()  // MasTests
            .deletingLastPathComponent()  // Mas (project root)
    }()

    /// mas-cli バイナリの想定パス。
    static let cliBinary: URL = {
        projectRoot.appendingPathComponent("CLI/mas-cli")
    }()

    /// build.sh の想定パス。
    static let buildScript: URL = {
        projectRoot.appendingPathComponent("CLI/build.sh")
    }()

    /// テストランあたり 1 回だけ実行されるビルドフラグ。
    private static var didBuild: Bool = false

    /// mas-cli バイナリを必要なら一度だけビルドする。
    /// 既にバイナリが存在していてもソース変更を反映するため毎テストランの初回 1 回はビルドを行う。
    static func ensureBuilt() {
        guard !didBuild else { return }
        defer { didBuild = true }

        guard FileManager.default.fileExists(atPath: buildScript.path) else {
            XCTFail("build.sh が見つかりません: \(buildScript.path)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [buildScript.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // 出力は捨てる

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            XCTFail("mas-cli の build.sh 実行に失敗: \(error)")
            return
        }

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "<no stderr>"
            XCTFail("mas-cli build.sh が exit code \(process.terminationStatus) で失敗: \(errorOutput)")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: cliBinary.path) else {
            XCTFail("ビルド後も mas-cli バイナリが見つからない/実行不可: \(cliBinary.path)")
            return
        }
    }

    /// CLI 実行結果。
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// `mas-cli <args...>` を実行して結果を返す。
    /// バイナリ未ビルド時は `ensureBuilt()` を呼んでから実行する。
    /// - Parameter args: CLI に渡す引数。例: `["version"]`、`["annotate", "in.png", "arrow", ...]`
    /// - Parameter timeout: 秒数。超えたら kill する。デフォルト 30 秒。
    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 30) -> Result {
        ensureBuilt()

        let process = Process()
        process.executableURL = cliBinary
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: "Process.run failed: \(error)")
        }

        // タイムアウト監視
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
