import XCTest
import AppKit
import CoreGraphics
@testable import Mas

final class RecaptureRegressionTests: XCTestCase {

    /// テスト用の region と screen を用意するヘルパー。
    private func makeFixture() -> (region: CGRect, screen: NSScreen, capturer: MockScreenCapturing, sleeper: MockSleeper) {
        guard let screen = NSScreen.main else {
            XCTFail("NSScreen.main not available in test environment")
            fatalError()
        }
        // region は screen.cgFrame の中心 200x200
        let cg = screen.cgFrame
        let region = CGRect(
            x: cg.origin.x + cg.width / 2 - 100,
            y: cg.origin.y + cg.height / 2 - 100,
            width: 200,
            height: 200
        )
        let imageWidth = Int(screen.frame.width * 2)  // Retina 想定
        let imageHeight = Int(screen.frame.height * 2)
        let stub = MockScreenCapturing.makeSolidImage(width: imageWidth, height: imageHeight)
        return (region, screen, MockScreenCapturing(stubImage: stub), MockSleeper())
    }

    // 通常モードでは sleep が呼ばれない（v3.6.6 sleep 削除回帰の逆方向: 通常モードで sleep が走り続けたら即時パシャが壊れる）
    func test_normalMode_skipsSleepAndHideWindow() async throws {
        let (region, screen, capturer, sleeper) = makeFixture()
        let flow = RecaptureFlow(capturer: capturer, sleeper: sleeper, isDevMode: false)

        var hideCalled = false
        let result = try await flow.run(
            region: region,
            screen: screen,
            hideWindow: { hideCalled = true }
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(sleeper.sleepCallCount, 0, "通常モードでは sleep してはならない（即時パシャ）")
        XCTAssertFalse(hideCalled, "通常モードでは hide コールバックを呼んではならない")
        XCTAssertEqual(capturer.captureScreenCallCount, 1)
    }

    // 開発モードでは hide → sleep 200ms → capture の順
    func test_devMode_sleeps200msBeforeCapture() async throws {
        let (region, screen, capturer, sleeper) = makeFixture()
        let flow = RecaptureFlow(capturer: capturer, sleeper: sleeper, isDevMode: true)

        var hideCalled = false
        let result = try await flow.run(
            region: region,
            screen: screen,
            hideWindow: { hideCalled = true }
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(hideCalled, "開発モードでは hide コールバックを呼ぶ")
        XCTAssertEqual(sleeper.sleepCallCount, 1, "開発モードで 1 回 sleep する")
        XCTAssertEqual(sleeper.totalSleepNanoseconds, 200_000_000, "sleep 時間は 200ms")
        XCTAssertEqual(capturer.captureScreenCallCount, 1)
    }

    // 渡された region がそのまま結果に反映される（v3.6.6 のように画像が古いまま、にならない）
    func test_resultRegionEqualsInputRegion() async throws {
        let (region, screen, capturer, sleeper) = makeFixture()
        let flow = RecaptureFlow(capturer: capturer, sleeper: sleeper, isDevMode: false)

        let result = try await flow.run(
            region: region,
            screen: screen,
            hideWindow: {}
        )

        XCTAssertEqual(result?.region, region, "渡した region がそのまま結果に反映される")
    }

    // region が画面外で空になる場合は nil を返す（早期 return）
    func test_emptyRegionReturnsNil() async throws {
        guard let screen = NSScreen.main else { fatalError() }
        let cg = screen.cgFrame
        // 画面から完全に外れた region
        let outOfBoundsRegion = CGRect(
            x: cg.maxX + 1000,
            y: cg.maxY + 1000,
            width: 100,
            height: 100
        )
        let imageWidth = Int(screen.frame.width * 2)
        let imageHeight = Int(screen.frame.height * 2)
        let stub = MockScreenCapturing.makeSolidImage(width: imageWidth, height: imageHeight)
        let capturer = MockScreenCapturing(stubImage: stub)
        let sleeper = MockSleeper()
        let flow = RecaptureFlow(capturer: capturer, sleeper: sleeper, isDevMode: false)

        let result = try await flow.run(
            region: outOfBoundsRegion,
            screen: screen,
            hideWindow: {}
        )

        XCTAssertNil(result, "画面外の region は nil を返す（早期 return）")
    }

    // captureScreen がエラーを投げると flow も投げる
    func test_capturerThrowsErrorPropagates() async throws {
        guard let screen = NSScreen.main else { fatalError() }
        let region = CGRect(x: screen.cgFrame.minX, y: screen.cgFrame.minY, width: 100, height: 100)

        struct DummyError: Error {}
        final class ThrowingCapturer: ScreenCapturing {
            func captureScreen(_ screen: NSScreen) async throws -> CGImage { throw DummyError() }
        }

        let flow = RecaptureFlow(
            capturer: ThrowingCapturer(),
            sleeper: MockSleeper(),
            isDevMode: false
        )

        do {
            _ = try await flow.run(region: region, screen: screen, hideWindow: {})
            XCTFail("Expected error to be thrown")
        } catch is DummyError {
            // OK
        }
    }
}
