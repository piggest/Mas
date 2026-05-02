# 単体テスト導入 Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mas プロジェクトの recapture など AppKit 依存ロジックをテスト可能にするため、`ScreenCapturing` / `SleepProviding` プロトコルと `RecaptureFlow` 純粋ロジックを切り出し、Mock を使った回帰テストで v3.6.6 の sleep 削除回帰バグを再発防止する。

**Architecture:** AppKit 依存 API（画面キャプチャ、`Task.sleep`）をプロトコルでラップ。`CaptureViewModel.recaptureRegion` のロジック部分（hide → sleep → capture → crop → 結果返却）を `RecaptureFlow` 構造体に抽出。実本番は実装、テストは Mock 注入で「呼ばれた region」「sleep 回数と総 ns」を検証。

**Tech Stack:** Swift 5, XCTest, async/await, Protocol-based DI

---

## File Structure

### 新規作成

```
Mas/
├── Adapters/
│   ├── ScreenCapturing.swift          ← Task 1
│   └── SleepProviding.swift           ← Task 2
├── Logic/
│   └── RecaptureFlow.swift            ← Task 3
MasTests/
├── Mocks/
│   ├── MockScreenCapturing.swift      ← Task 1
│   └── MockSleeper.swift              ← Task 2
└── Regression/
    └── RecaptureRegressionTests.swift ← Task 4
```

### 変更

- `Mas/Services/ScreenCaptureService.swift` — `ScreenCapturing` プロトコル準拠を宣言
- `Mas/ViewModels/CaptureViewModel.swift` — `recaptureRegion` を `RecaptureFlow` 経由に書き換え

---

## Task 1: ScreenCapturing プロトコル + Mock

**Files:**
- Create: `Mas/Adapters/ScreenCapturing.swift`
- Create: `MasTests/Mocks/MockScreenCapturing.swift`
- Modify: `Mas/Services/ScreenCaptureService.swift`

- [ ] **Step 1.1: ScreenCapturing プロトコル作成**

`Mas/Adapters/ScreenCapturing.swift`:

```swift
import AppKit
import CoreGraphics

/// 画面キャプチャを抽象化するプロトコル。テストでは Mock を注入する。
protocol ScreenCapturing {
    func captureScreen(_ screen: NSScreen) async throws -> CGImage
}
```

- [ ] **Step 1.2: ScreenCaptureService をプロトコル準拠**

`Mas/Services/ScreenCaptureService.swift` のクラス宣言に `ScreenCapturing` を追加：

```swift
// 変更前
class ScreenCaptureService: NSObject {
```

```swift
// 変更後
class ScreenCaptureService: NSObject, ScreenCapturing {
```

`captureScreen(_ screen:)` のシグネチャは既に一致しているので追加実装不要。

- [ ] **Step 1.3: ヘルパーで Adapters/ScreenCapturing.swift を ScreenshotApp ターゲットに登録**

```bash
cd /Users/norifumi.okumura/Mas
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb Mas/Adapters/ScreenCapturing.swift ScreenshotApp
```

- [ ] **Step 1.4: ビルド確認**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`、既存 34 tests pass。

- [ ] **Step 1.5: MockScreenCapturing を作成**

`MasTests/Mocks/MockScreenCapturing.swift`:

```swift
import AppKit
import CoreGraphics
@testable import Mas

/// captureScreen 呼び出しを記録し、事前設定した CGImage を返す Mock。
final class MockScreenCapturing: ScreenCapturing {

    /// captureScreen が呼ばれたときに返す画像。
    var stubImage: CGImage

    /// captureScreen が呼ばれた回数。
    private(set) var captureScreenCallCount: Int = 0

    /// captureScreen に渡された screen の履歴。
    private(set) var capturedScreens: [NSScreen] = []

    init(stubImage: CGImage) {
        self.stubImage = stubImage
    }

    func captureScreen(_ screen: NSScreen) async throws -> CGImage {
        captureScreenCallCount += 1
        capturedScreens.append(screen)
        return stubImage
    }
}

extension MockScreenCapturing {
    /// テスト用に単色の CGImage を作る簡易ファクトリ。
    static func makeSolidImage(width: Int, height: Int, color: CGColor = CGColor(gray: 0.5, alpha: 1.0)) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
```

- [ ] **Step 1.6: ヘルパーで MockScreenCapturing.swift を MasTests ターゲットに登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb MasTests/Mocks/MockScreenCapturing.swift MasTests
```

- [ ] **Step 1.7: ビルド確認**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: 引き続き全 34 tests pass。

- [ ] **Step 1.8: Commit**

```bash
git add Mas/Adapters/ScreenCapturing.swift Mas/Services/ScreenCaptureService.swift MasTests/Mocks/MockScreenCapturing.swift Mas.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor: ScreenCapturing プロトコルと Mock を追加

ScreenCaptureService に ScreenCapturing 準拠を宣言し、テスト用 MockScreenCapturing を追加。
recapture フローの DI 化と回帰テストの土台。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: SleepProviding プロトコル + Mock

**Files:**
- Create: `Mas/Adapters/SleepProviding.swift`
- Create: `MasTests/Mocks/MockSleeper.swift`

- [ ] **Step 2.1: SleepProviding プロトコル作成**

`Mas/Adapters/SleepProviding.swift`:

```swift
import Foundation

/// 非同期 sleep を抽象化するプロトコル。テストでは即時化される Mock を注入する。
protocol SleepProviding {
    func sleep(nanoseconds: UInt64) async
}

/// 実本番の Sleep。`Task.sleep` をラップする。
struct RealSleeper: SleepProviding {
    func sleep(nanoseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
```

- [ ] **Step 2.2: ヘルパーで登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb Mas/Adapters/SleepProviding.swift ScreenshotApp
```

- [ ] **Step 2.3: ビルド確認**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -5
```

- [ ] **Step 2.4: MockSleeper を作成**

`MasTests/Mocks/MockSleeper.swift`:

```swift
import Foundation
@testable import Mas

/// sleep 呼び出しを記録し、実際にはスリープしない Mock。
final class MockSleeper: SleepProviding {

    /// sleep が呼ばれた回数。
    private(set) var sleepCallCount: Int = 0

    /// 各 sleep 呼び出しの ns 引数履歴。
    private(set) var sleepNanoseconds: [UInt64] = []

    /// sleep 呼び出しの ns 合計。
    var totalSleepNanoseconds: UInt64 {
        sleepNanoseconds.reduce(0, +)
    }

    func sleep(nanoseconds: UInt64) async {
        sleepCallCount += 1
        sleepNanoseconds.append(nanoseconds)
        // 実際にはスリープしない（テスト即時化）
    }
}
```

- [ ] **Step 2.5: ヘルパーで登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb MasTests/Mocks/MockSleeper.swift MasTests
```

- [ ] **Step 2.6: ビルド確認**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: 全 34 tests pass。

- [ ] **Step 2.7: Commit**

```bash
git add Mas/Adapters/SleepProviding.swift MasTests/Mocks/MockSleeper.swift Mas.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor: SleepProviding プロトコルと Mock を追加

Task.sleep を抽象化し、テストでは MockSleeper で即時化＆呼び出し検証可能に。
recapture フローの DI 化と回帰テストの土台。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: RecaptureFlow 切り出し

**Files:**
- Create: `Mas/Logic/RecaptureFlow.swift`
- Modify: `Mas/ViewModels/CaptureViewModel.swift`

`CaptureViewModel.recaptureRegion` のうち、AppKit 状態（NSWindow）を除いた部分を `RecaptureFlow` に集約する。

### 切り出すロジック範囲

- 引数: region (CGRect)、isDevMode (Bool)、対象スクリーンを取得する関数
- 処理:
  1. 開発モード時: hideWindow コールバック呼び出し → sleep 200ms
  2. region から対象スクリーンを取得（呼び出し側で渡す）
  3. captureScreen 実行
  4. CropMath で region に crop
  5. 結果（CGImage と region）または nil を返す
- 残す: NSWindow の orderOut/makeKeyAndOrderFront、screenshot.updateImage 等の AppKit 状態更新は呼び出し側

- [ ] **Step 3.1: RecaptureFlow 構造体作成**

`Mas/Logic/RecaptureFlow.swift`:

```swift
import AppKit
import CoreGraphics

/// recapture の純粋フロー部分（DI 可能・テスト可能）。
/// AppKit の `NSWindow` 状態更新（orderOut/makeKeyAndOrderFront）や `Screenshot` 状態更新は
/// 呼び出し側に残し、ここでは「画面キャプチャ → crop → 結果」のみを扱う。
struct RecaptureFlow {

    let capturer: ScreenCapturing
    let sleeper: SleepProviding
    /// 隠す処理を行うかどうかを判定する isDevMode の値。
    let isDevMode: Bool

    /// 開発モード時の事前 sleep 時間（ns）。
    static let devModeSleepNanoseconds: UInt64 = 200_000_000

    /// recapture 処理の結果。
    struct Result {
        /// 切り出された CGImage。
        let croppedImage: CGImage
        /// 実際に使った region。
        let region: CGRect
    }

    /// 指定された region で recapture を実行する。
    /// - Parameters:
    ///   - region: CG 座標系のキャプチャ範囲（呼び出し側で `window.frame` から計算）
    ///   - screen: region が属するスクリーン
    ///   - hideWindow: 開発モード時に呼ばれる、ウィンドウを隠すコールバック（main 外で呼ばれる可能性あり）
    /// - Returns: 成功時は Result、失敗（範囲外など）時は nil
    func run(
        region: CGRect,
        screen: NSScreen,
        hideWindow: @MainActor () -> Void
    ) async throws -> Result? {

        // 開発モード時のみ事前に隠して待つ（通常モードは sharingType=.none で自身が映らない）
        if isDevMode {
            await MainActor.run { hideWindow() }
            await sleeper.sleep(nanoseconds: Self.devModeSleepNanoseconds)
        }

        let fullScreenImage = try await capturer.captureScreen(screen)

        let imageWidth = CGFloat(fullScreenImage.width)
        let imageHeight = CGFloat(fullScreenImage.height)
        let scale = CropMath.imageScale(imageWidth: imageWidth, screenWidth: screen.frame.width)

        let scaledRect = CropMath.scaledRect(region: region, screenCGFrame: screen.cgFrame, scale: scale)
        let clampedRect = CropMath.clampedRect(scaledRect, imageSize: CGSize(width: imageWidth, height: imageHeight))

        guard !clampedRect.isEmpty, let croppedImage = fullScreenImage.cropping(to: clampedRect) else {
            return nil
        }

        return Result(croppedImage: croppedImage, region: region)
    }
}
```

- [ ] **Step 3.2: ヘルパーで登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb Mas/Logic/RecaptureFlow.swift ScreenshotApp
```

- [ ] **Step 3.3: ビルド確認**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -5
```

- [ ] **Step 3.4: CaptureViewModel.recaptureRegion を RecaptureFlow 経由に書き換え**

`Mas/ViewModels/CaptureViewModel.swift` の現在の実装：

```swift
// 変更前
func recaptureRegion(for screenshot: Screenshot, at region: CGRect, window: NSWindow?, hideWindow: Bool = true) async {
    let isDevMode = UserDefaults.standard.bool(forKey: "includeOwnUI")
    let needsHide = hideWindow && isDevMode
    if needsHide {
        window?.orderOut(nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    do {
        guard let screen = NSScreen.screenContaining(cgRect: region) else {
            if needsHide { window?.makeKeyAndOrderFront(nil) }
            return
        }

        let fullScreenImage = try await captureService.captureScreen(screen)

        let imageWidth = CGFloat(fullScreenImage.width)
        let imageHeight = CGFloat(fullScreenImage.height)
        let scale = CropMath.imageScale(imageWidth: imageWidth, screenWidth: screen.frame.width)

        let screenCGFrame = screen.cgFrame
        let scaledRect = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: scale)
        let clampedRect = CropMath.clampedRect(scaledRect, imageSize: CGSize(width: imageWidth, height: imageHeight))

        guard !clampedRect.isEmpty, let croppedImage = fullScreenImage.cropping(to: clampedRect) else {
            if needsHide { window?.makeKeyAndOrderFront(nil) }
            return
        }

        captureFlash.showFlash(in: region)
        screenshot.updateImage(croppedImage)
        screenshot.captureRegion = region

        if screenshot.isGif {
            screenshot.savedURL = nil
        }

        if let resizableWindow = window as? ResizableWindow {
            resizableWindow.resizeState.reset()
        }

        processScreenshot(screenshot)
        objectWillChange.send()

        if needsHide { window?.makeKeyAndOrderFront(nil) }
    } catch {
        print("Recapture error: \(error)")
        if needsHide { window?.makeKeyAndOrderFront(nil) }
    }
}
```

```swift
// 変更後
private lazy var recaptureFlow = RecaptureFlow(
    capturer: captureService,
    sleeper: RealSleeper(),
    isDevMode: UserDefaults.standard.bool(forKey: "includeOwnUI")
)

func recaptureRegion(for screenshot: Screenshot, at region: CGRect, window: NSWindow?, hideWindow: Bool = true) async {
    // 毎回最新の isDevMode を反映するため flow を作り直す
    let isDevMode = UserDefaults.standard.bool(forKey: "includeOwnUI")
    let flow = RecaptureFlow(
        capturer: captureService,
        sleeper: RealSleeper(),
        isDevMode: isDevMode
    )

    let needsShowAfter = hideWindow && isDevMode

    do {
        guard let screen = NSScreen.screenContaining(cgRect: region) else {
            return
        }

        let result = try await flow.run(
            region: region,
            screen: screen,
            hideWindow: { window?.orderOut(nil) }
        )

        guard let result else {
            if needsShowAfter { window?.makeKeyAndOrderFront(nil) }
            return
        }

        captureFlash.showFlash(in: region)
        screenshot.updateImage(result.croppedImage)
        screenshot.captureRegion = result.region

        if screenshot.isGif {
            screenshot.savedURL = nil
        }

        if let resizableWindow = window as? ResizableWindow {
            resizableWindow.resizeState.reset()
        }

        processScreenshot(screenshot)
        objectWillChange.send()

        if needsShowAfter { window?.makeKeyAndOrderFront(nil) }
    } catch {
        print("Recapture error: \(error)")
        if needsShowAfter { window?.makeKeyAndOrderFront(nil) }
    }
}
```

注: `private lazy var recaptureFlow` は将来の DI 用に残してもよいが、isDevMode が動的に変わるので run 毎に作り直すのが安全。

- [ ] **Step 3.5: ビルド + 全テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全 34 tests pass。

- [ ] **Step 3.6: 実機動作確認**

```bash
xcodebuild -scheme ScreenshotApp -configuration Debug build 2>&1 | tail -3
killall -9 Mas 2>&1 || true; sleep 1
rm -rf /Applications/Mas.app
cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/
open /Applications/Mas.app
```

範囲選択 → 移動 → 再キャプチャ → 新位置の内容が反映されることを目視確認。

- [ ] **Step 3.7: Commit**

```bash
git add Mas/Logic/RecaptureFlow.swift Mas/ViewModels/CaptureViewModel.swift Mas.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor: recapture フローを RecaptureFlow に切り出し

CaptureViewModel.recaptureRegion から「画面キャプチャ → crop → 結果」のロジック部分を
Mas/Logic/RecaptureFlow.swift の構造体に集約。ScreenCapturing と SleepProviding の
DI を受けるためテストで Mock 注入可能に。挙動同等。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: recapture 回帰テスト

**Files:**
- Create: `MasTests/Regression/RecaptureRegressionTests.swift`

`RecaptureFlow` を直接テストする。Mock の screen は `NSScreen.main!` を使う（テスト環境にスクリーンが必須、CI で動かす場合は head 環境）。

- [ ] **Step 4.1: RecaptureRegressionTests を作成**

`MasTests/Regression/RecaptureRegressionTests.swift`:

```swift
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

    // 通常モードでは sleep が呼ばれない（v3.6.6 sleep 削除回帰の逆方向）
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
```

- [ ] **Step 4.2: ヘルパーで登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb MasTests/Regression/RecaptureRegressionTests.swift MasTests
```

- [ ] **Step 4.3: テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -15
```

Expected: 全 39 tests pass（既存 34 + 新規 5）、`** TEST SUCCEEDED **`。

- [ ] **Step 4.4: Commit**

```bash
git add MasTests/Regression/RecaptureRegressionTests.swift Mas.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
test: recapture フローの回帰テスト追加

v3.6.6 の sleep 削除回帰（通常モードで sleep が走り続けたら即時パシャが
壊れる、または sleep を完全消去すると開発モードで自UI映り込み）を再発
させないため、RecaptureFlow を Mock を使ってテスト。
- 通常モード: sleep/hide が呼ばれない
- 開発モード: hide → sleep 200ms → capture の順で 1 回ずつ
- 結果 region が入力 region と一致する
- 画面外 region は nil
- capturer エラーは伝播

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 動作確認 + Phase 2 完了

- [ ] **Step 5.1: 全テスト実行**

```bash
cd /Users/norifumi.okumura/Mas
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -25
```

Expected:
- `RecaptureRegressionTests` 5 ケース pass
- 既存全 pass
- `** TEST SUCCEEDED **`
- 合計 39 tests

- [ ] **Step 5.2: 実機動作確認**

```bash
xcodebuild -scheme ScreenshotApp -configuration Debug build 2>&1 | tail -3
killall -9 Mas 2>&1 || true; sleep 1
rm -rf /Applications/Mas.app
cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/
open /Applications/Mas.app
```

シナリオ：
1. 範囲選択キャプチャ → OK
2. 枠を移動 → 右上ボタンで再キャプチャ → 新位置の内容反映
3. 開発モード ON で同じ操作 → 自UI映り込みなし
4. annotation 描画・リサイズ → 既存挙動
5. ファイルドロップ → 既存挙動

- [ ] **Step 5.3: コミット履歴確認**

```bash
git log --oneline main..HEAD
```

Phase 2 のコミット 4-5 個程度が並ぶこと：
- `refactor: ScreenCapturing プロトコルと Mock を追加`
- `refactor: SleepProviding プロトコルと Mock を追加`
- `refactor: recapture フローを RecaptureFlow に切り出し`
- `test: recapture フローの回帰テスト追加`

---

## Self-Review

完了報告時にこのチェックリストを通す：

- [ ] Phase 2 spec 要件カバー：
  - [x] `ScreenCapturing` プロトコル + Mock
  - [x] `SleepProviding` プロトコル + Mock
  - [x] `RecaptureFlow` 切り出し
  - [x] recapture 回帰テスト 5 ケース
- [ ] 既存挙動の回帰なし（手動 E2E 全パス）
- [ ] テスト数 39 ケース以上
- [ ] `xcodebuild test` が安定 pass

## Phase 3 への引き継ぎ

Phase 2 完了後、`docs/superpowers/specs/regression-backlog.md` を作成して過去バグの一覧化を始める（別 plan）。
