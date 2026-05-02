import AppKit
import XCTest
@testable import Mas

/// CLI（mas-cli）の annotate コマンドの E2E テスト。
/// 各アノテーション種別（arrow / rect / ellipse / text / highlight / mosaic）が
/// 画像に正しく焼き付け処理を完走し、PNG として保存されることを検証する。
final class CliAnnotateTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        CliRunner.ensureBuilt()
    }

    /// 各テストで使う一時ディレクトリ。tearDown でクリーンアップ。
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("mas-cli-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tmpDir = tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        super.tearDown()
    }

    // MARK: - ヘルパ

    /// 単色（白）の PNG を tmpDir 内に生成し、URL を返す。
    private func makeWhitePNG(width: Int = 400, height: Int = 300) -> URL {
        let url = tmpDir.appendingPathComponent("input.png")
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("白色 PNG の生成に失敗")
            return url
        }
        try? pngData.write(to: url)
        return url
    }

    /// 出力 PNG が有効な画像であり、想定サイズ範囲内であることを検証する。
    private func assertValidPNG(_ url: URL, expectedWidth: Int, expectedHeight: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "出力ファイルが存在しない: \(url.path)", file: file, line: line)

        guard let image = NSImage(contentsOf: url) else {
            XCTFail("出力 PNG が NSImage で読めない: \(url.path)", file: file, line: line)
            return
        }
        // アノテーションが画像内に収まる場合、サイズは元と同じ。はみ出す場合は拡張される。
        // 元サイズ以上を要件とする。
        XCTAssertGreaterThanOrEqual(Int(image.size.width), expectedWidth, "出力幅が小さい", file: file, line: line)
        XCTAssertGreaterThanOrEqual(Int(image.size.height), expectedHeight, "出力高さが小さい", file: file, line: line)
    }

    // MARK: - 各アノテーション種別

    func test_annotate_arrow_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("arrow.png")

        let result = CliRunner.run([
            "annotate", input.path, "arrow",
            "--from", "50,50",
            "--to", "200,200",
            "--color", "red",
            "--width", "4",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "arrow annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    func test_annotate_rect_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("rect.png")

        let result = CliRunner.run([
            "annotate", input.path, "rect",
            "--rect", "30,30,150,100",
            "--color", "blue",
            "--width", "3",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "rect annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    func test_annotate_ellipse_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("ellipse.png")

        let result = CliRunner.run([
            "annotate", input.path, "ellipse",
            "--rect", "100,80,200,120",
            "--color", "green",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "ellipse annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    func test_annotate_text_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("text.png")

        let result = CliRunner.run([
            "annotate", input.path, "text",
            "--pos", "60,60",
            "--text", "Hello",
            "--size", "24",
            "--color", "black",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "text annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    func test_annotate_highlight_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("highlight.png")

        let result = CliRunner.run([
            "annotate", input.path, "highlight",
            "--rect", "20,20,160,40",
            "--color", "yellow",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "highlight annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    func test_annotate_mosaic_producesValidPNG() {
        let input = makeWhitePNG()
        let output = tmpDir.appendingPathComponent("mosaic.png")

        let result = CliRunner.run([
            "annotate", input.path, "mosaic",
            "--rect", "50,50,200,150",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0, "mosaic annotate が失敗: \(result.stderr)")
        assertValidPNG(output, expectedWidth: 400, expectedHeight: 300)
    }

    // MARK: - エラー系

    func test_annotate_missingInputFile_returnsNonZeroExit() {
        let result = CliRunner.run([
            "annotate", "/tmp/does-not-exist-\(UUID().uuidString).png", "arrow",
            "--from", "0,0", "--to", "10,10"
        ])
        XCTAssertNotEqual(result.exitCode, 0, "存在しない入力で exit 0 になっている: stdout=\(result.stdout)")
    }

    func test_annotate_missingType_returnsNonZeroExit() {
        let input = makeWhitePNG()
        let result = CliRunner.run(["annotate", input.path])
        XCTAssertNotEqual(result.exitCode, 0, "type 引数なしで exit 0 になっている: stdout=\(result.stdout)")
    }
}
