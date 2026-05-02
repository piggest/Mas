import AppKit
import XCTest
@testable import Mas

/// CLI（mas-cli）の ocr コマンドの E2E テスト。
/// 既知テキストを描画した画像から、Vision フレームワーク経由で OCR 結果を抽出できることを検証。
final class CliOCRTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        CliRunner.ensureBuilt()
    }

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("mas-cli-ocr-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tmpDir = tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        super.tearDown()
    }

    /// テキストを描画した PNG を tmpDir 内に作る。
    /// `NSBitmapImageRep` に NSGraphicsContext で直接描画する方式（NSImage.lockFocus 経由だと
    /// `tiffRepresentation` が CGImageDestinationFinalize で失敗するケースがある）。
    /// - Parameter text: 描画する文字列
    /// - Parameter fontSize: フォントサイズ（小さすぎると OCR 失敗）
    private func makeTextPNG(_ text: String, fontSize: CGFloat = 48) -> URL {
        let url = tmpDir.appendingPathComponent("ocr-input-\(UUID().uuidString).png")

        // 白背景 + 黒文字。OCR 精度を上げるためフォントサイズは大きめ
        let width = 800
        let height = 200

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("NSBitmapImageRep の確保に失敗")
            return url
        }

        guard let gc = NSGraphicsContext(bitmapImageRep: bitmap) else {
            XCTFail("NSGraphicsContext の生成に失敗")
            return url
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()
        attrString.draw(at: NSPoint(
            x: (CGFloat(width) - textSize.width) / 2,
            y: (CGFloat(height) - textSize.height) / 2
        ))

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("PNG 表現の生成に失敗")
            return url
        }
        try? pngData.write(to: url)
        return url
    }

    func test_ocr_recognizesEnglishText() {
        let input = makeTextPNG("Hello World")

        let result = CliRunner.run(["ocr", input.path])
        XCTAssertEqual(result.exitCode, 0, "ocr コマンドが失敗: \(result.stderr)")

        // OCR 結果は "Hello" や "World" を含むはず（完全一致は OCR 精度上保証しない）
        let output = result.stdout.lowercased()
        let containsHello = output.contains("hello")
        let containsWorld = output.contains("world")
        XCTAssertTrue(containsHello || containsWorld, "OCR 結果に Hello/World どちらも含まれない: \(result.stdout)")
    }

    func test_ocr_jsonFlag_returnsValidJSON() {
        let input = makeTextPNG("Sample")

        let result = CliRunner.run(["ocr", input.path, "--json"])
        XCTAssertEqual(result.exitCode, 0, "ocr --json コマンドが失敗: \(result.stderr)")

        // JSON としてパースできること
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            XCTFail("JSON 出力が UTF-8 でない")
            return
        }
        let json = try? JSONSerialization.jsonObject(with: data, options: [])
        XCTAssertNotNil(json, "OCR --json 出力が JSON としてパースできない: \(trimmed)")
    }

    func test_ocr_missingImagePath_returnsNonZeroExit() {
        let result = CliRunner.run(["ocr", "/tmp/does-not-exist-\(UUID().uuidString).png"])
        XCTAssertNotEqual(result.exitCode, 0, "存在しないパスで exit 0 になっている: stdout=\(result.stdout)")
    }

    func test_ocr_noArgs_returnsNonZeroExit() {
        let result = CliRunner.run(["ocr"])
        XCTAssertNotEqual(result.exitCode, 0, "引数なしで exit 0 になっている: stdout=\(result.stdout)")
    }
}
