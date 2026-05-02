import XCTest
@testable import Mas

/// CLI（mas-cli）の version / status / help 系コマンドの E2E テスト。
/// アプリ起動を必要としない読み取り系コマンドのみを対象とする。
final class CliVersionStatusTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        CliRunner.ensureBuilt()
    }

    func test_version_returnsHelpOrVersionString() {
        // version コマンドは "v3.4.2" のような形式をどこかに含むか、
        // help テキスト内に "version" 行を含む。
        let result = CliRunner.run(["version"])
        XCTAssertEqual(result.exitCode, 0, "exit code: \(result.exitCode), stderr: \(result.stderr)")

        let combined = result.stdout + result.stderr
        let hasVersionPattern = combined.range(of: #"v\d+\.\d+\.\d+"#, options: .regularExpression) != nil
            || combined.contains("version")
        XCTAssertTrue(hasVersionPattern, "version 出力に v?.?.? かつ 'version' 文字列がない: \(combined)")
    }

    func test_help_listsExpectedCommands() {
        // 引数なしまたは未知コマンドで help が出る
        let result = CliRunner.run([])
        // help を出してから exit 1 でも 0 でもよい
        let combined = result.stdout + result.stderr

        // 主要コマンドが列挙されていること
        XCTAssertTrue(combined.contains("capture"), "capture コマンドが help に列挙されていない")
        XCTAssertTrue(combined.contains("annotate"), "annotate コマンドが help に列挙されていない")
        XCTAssertTrue(combined.contains("ocr"), "ocr コマンドが help に列挙されていない")
        XCTAssertTrue(combined.contains("history"), "history コマンドが help に列挙されていない")
    }

    func test_status_returnsKnownState() {
        // status は「起動中」「未起動」のどちらかを返す。文字列内容は問わず、
        // 0 で終わる + 何かしら出力があることだけ確認。
        let result = CliRunner.run(["status"])
        XCTAssertEqual(result.exitCode, 0, "exit code: \(result.exitCode), stderr: \(result.stderr)")
        XCTAssertFalse(
            (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "status コマンドの出力が空"
        )
    }

    func test_unknownCommand_returnsNonZeroExit() {
        let result = CliRunner.run(["unknown_command_xyz"])
        XCTAssertNotEqual(result.exitCode, 0, "未知コマンドが exit 0 で終了している: stdout=\(result.stdout)")
    }
}
