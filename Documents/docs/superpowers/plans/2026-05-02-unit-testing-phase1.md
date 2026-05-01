# 単体テスト導入 Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mas プロジェクトに `MasTests` テストターゲットを追加し、`Mas/Logic/` 配下に 4 つの純粋ロジックモジュール（`CoordinateMath`, `CropMath`, `CaptureRegionMath`, `AnnotationGeometry`）を切り出して XCTest でカバーする。release 系スキルと CLAUDE.md にテスト実行を必須化するルールを追加する。

**Architecture:** 既存の AppKit 依存コードから純粋計算を `enum` の static メソッドとして抽出。既存の呼び出し箇所はラッパとして純粋ロジックを呼び出す形に書き換え、挙動同等を保つ。テストは `MasTests/PureLogic/` 以下に各モジュール 5〜10 ケースずつ。

**Tech Stack:** Swift 5, XCTest, Xcode 16+, macOS 13+

---

## File Structure

### 新規作成

```
Mas/
├── Logic/
│   ├── CoordinateMath.swift          ← NS↔CG 変換
│   ├── CropMath.swift                ← scaledRect/clampedRect 計算
│   ├── CaptureRegionMath.swift       ← window frame ↔ CGRect、resize 計算
│   └── AnnotationGeometry.swift      ← annotation の境界/リサイズ計算
├── ...
MasTests/                              ← 新規ターゲット
├── SmokeTests.swift                   ← Task 1
├── PureLogic/
│   ├── CoordinateMathTests.swift
│   ├── CropMathTests.swift
│   ├── CaptureRegionMathTests.swift
│   └── AnnotationGeometryTests.swift
```

### 変更

- `Mas.xcodeproj/project.pbxproj` (MasTests ターゲット追加)
- `Mas/Services/ScreenCaptureService.swift` (NSScreen extension が `CoordinateMath` を呼ぶ形に)
- `Mas/ViewModels/CaptureViewModel.swift` (`recaptureRegion` 内が `CropMath` を呼ぶ形に)
- `Mas/Views/EditorWindow.swift` (`getCurrentWindowRect`, `setContentScale`, トリミング処理が `CaptureRegionMath` を呼ぶ形に)
- `Mas/Models/Annotations/*.swift` (各 `boundingRect()` が `AnnotationGeometry` を呼ぶ形に)
- `Mas/CLAUDE.md` (テストセクション追加)
- `~/.claude/skills/release/SKILL.md`, `~/.claude/skills/minor-release/SKILL.md`, `~/.claude/skills/major-release/SKILL.md` (手順0追加)

---

## Task 1: MasTests ターゲット追加 + smoke test

**Files:**
- Create: `MasTests/SmokeTests.swift`
- Modify: `Mas.xcodeproj/project.pbxproj` (Xcode GUI で追加)

- [ ] **Step 1.1: Xcode で MasTests ターゲットを追加**

```
1. Xcode で `Mas.xcodeproj` を開く
2. メニュー: File > New > Target...
3. macOS タブから「Unit Testing Bundle」を選択 → Next
4. Product Name: `MasTests`
   Team: (既存と同じ)
   Organization Identifier: com.example
   Bundle Identifier: com.example.MasTests
   Language: Swift
   Project: Mas
   Target to be Tested: ScreenshotApp
   → Finish
5. 自動生成された `MasTests/MasTests.swift` は削除
6. Xcode を閉じる
```

- [ ] **Step 1.2: smoke test を作成**

`MasTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Mas

final class SmokeTests: XCTestCase {
    func test_smoke_basic_assertion_passes() {
        XCTAssertEqual(1 + 1, 2)
    }
}
```

注: `@testable import Mas` の "Mas" 部分は実際の Module 名。Xcode が自動設定する。Build Settings の `PRODUCT_MODULE_NAME` を確認。`ScreenshotApp` の場合は `@testable import ScreenshotApp` に変更する。

- [ ] **Step 1.3: テスト実行確認**

```bash
cd /Users/norifumi.okumura/Mas
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `Test Suite 'SmokeTests' passed`、`** TEST SUCCEEDED **`

- [ ] **Step 1.4: Commit**

```bash
git add MasTests/ Mas.xcodeproj/project.pbxproj
git commit -m "test: MasTests ターゲット追加 + smoke test"
```

---

## Task 2: CoordinateMath 抽出

**Files:**
- Create: `Mas/Logic/CoordinateMath.swift`
- Create: `MasTests/PureLogic/CoordinateMathTests.swift`
- Modify: `Mas/Services/ScreenCaptureService.swift`

- [ ] **Step 2.1: 失敗するテストを書く**

`MasTests/PureLogic/CoordinateMathTests.swift`:

```swift
import XCTest
@testable import ScreenshotApp

final class CoordinateMathTests: XCTestCase {

    // 単一スクリーン (primaryHeight=1080) で原点 (0,0) の点が NS↔CG で対称に変換される
    func test_nsToCG_originIsSymmetric() {
        let primaryHeight: CGFloat = 1080
        let nsRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let cgRect = CoordinateMath.nsToCG(nsRect, primaryHeight: primaryHeight)
        XCTAssertEqual(cgRect.origin.x, 0)
        XCTAssertEqual(cgRect.origin.y, 980)  // 1080 - 0 - 100
        XCTAssertEqual(cgRect.width, 100)
        XCTAssertEqual(cgRect.height, 100)
    }

    func test_cgToNS_isInverseOfNsToCG() {
        let primaryHeight: CGFloat = 1117
        let original = CGRect(x: 200, y: 300, width: 400, height: 500)
        let cg = CoordinateMath.nsToCG(original, primaryHeight: primaryHeight)
        let backToNs = CoordinateMath.cgToNS(cg, primaryHeight: primaryHeight)
        XCTAssertEqual(backToNs.origin.x, original.origin.x, accuracy: 0.0001)
        XCTAssertEqual(backToNs.origin.y, original.origin.y, accuracy: 0.0001)
        XCTAssertEqual(backToNs.width, original.width, accuracy: 0.0001)
        XCTAssertEqual(backToNs.height, original.height, accuracy: 0.0001)
    }

    func test_cgFrameForScreen_primaryScreenOriginIsZero() {
        // primary screen は NS 座標 (0,0) 起点・height = 1117 の場合
        let nsFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let primaryHeight: CGFloat = 1117
        let cg = CoordinateMath.cgFrameForScreen(nsFrame: nsFrame, primaryHeight: primaryHeight)
        XCTAssertEqual(cg, CGRect(x: 0, y: 0, width: 1728, height: 1117))
    }

    func test_cgFrameForScreen_secondaryAboveOnly() {
        // secondary が primary の上にある場合（NS 座標で y > 0）
        let nsFrame = CGRect(x: 0, y: 1117, width: 1920, height: 1080)
        let primaryHeight: CGFloat = 1117
        let cg = CoordinateMath.cgFrameForScreen(nsFrame: nsFrame, primaryHeight: primaryHeight)
        // CG では primary の上に secondary が来る → cg.y は負
        XCTAssertEqual(cg.origin.x, 0)
        XCTAssertEqual(cg.origin.y, -1080)  // 1117 - 1117 - 1080
        XCTAssertEqual(cg.width, 1920)
        XCTAssertEqual(cg.height, 1080)
    }

    func test_nsToCG_negativeOriginX() {
        // primary の左にあるスクリーン
        let primaryHeight: CGFloat = 1117
        let nsRect = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let cg = CoordinateMath.nsToCG(nsRect, primaryHeight: primaryHeight)
        XCTAssertEqual(cg.origin.x, -1920)
        XCTAssertEqual(cg.origin.y, 37)  // 1117 - 0 - 1080
    }
}
```

- [ ] **Step 2.2: テスト実行（失敗確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | grep -E "error|FAIL" | head
```

Expected: `Cannot find 'CoordinateMath' in scope` というエラー

- [ ] **Step 2.3: 最小実装**

`Mas/Logic/CoordinateMath.swift`:

```swift
import CoreGraphics

/// NS 座標系（左下原点）と CG 座標系（左上原点）の純粋計算。
/// AppKit/UIKit に依存しない値型のみで完結する。
enum CoordinateMath {

    /// NS 矩形を CG 矩形に変換する。primaryHeight は NSScreen.screens[0].frame.height。
    static func nsToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// CG 矩形を NS 矩形に変換する。
    static func cgToNS(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// スクリーン NS frame から CG frame を計算する。
    static func cgFrameForScreen(nsFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        nsToCG(nsFrame, primaryHeight: primaryHeight)
    }
}
```

- [ ] **Step 2.4: テスト実行（成功確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Test Suite 'CoordinateMathTests' passed`

- [ ] **Step 2.5: 既存呼び出しを CoordinateMath 経由に置換**

`Mas/Services/ScreenCaptureService.swift` の NSScreen extension を変更：

```swift
// 変更前
extension NSScreen {
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens[0].frame.height
    }

    var cgFrame: CGRect {
        let primaryHeight = NSScreen.primaryScreenHeight
        return CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

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
```

```swift
// 変更後
extension NSScreen {
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens[0].frame.height
    }

    var cgFrame: CGRect {
        CoordinateMath.cgFrameForScreen(nsFrame: frame, primaryHeight: NSScreen.primaryScreenHeight)
    }

    static func cgToNS(_ cgRect: CGRect) -> NSRect {
        CoordinateMath.cgToNS(cgRect, primaryHeight: NSScreen.primaryScreenHeight)
    }
}
```

- [ ] **Step 2.6: ビルド + テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass、`** TEST SUCCEEDED **`

- [ ] **Step 2.7: 手動動作確認**

```bash
xcodebuild -scheme ScreenshotApp -configuration Debug build 2>&1 | tail -3
killall -9 Mas 2>&1 || true; sleep 1
rm -rf /Applications/Mas.app
cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/
open /Applications/Mas.app
```

Mas を起動して、範囲選択キャプチャ・移動・再キャプチャが動くことを目視確認。

- [ ] **Step 2.8: Commit**

```bash
git add Mas/Logic/CoordinateMath.swift MasTests/PureLogic/CoordinateMathTests.swift Mas/Services/ScreenCaptureService.swift
git commit -m "refactor: 座標変換を CoordinateMath に抽出してテスト追加"
```

---

## Task 3: CropMath 抽出

**Files:**
- Create: `Mas/Logic/CropMath.swift`
- Create: `MasTests/PureLogic/CropMathTests.swift`
- Modify: `Mas/ViewModels/CaptureViewModel.swift`

- [ ] **Step 3.1: 失敗するテストを書く**

`MasTests/PureLogic/CropMathTests.swift`:

```swift
import XCTest
@testable import ScreenshotApp

final class CropMathTests: XCTestCase {

    func test_scaledRect_primaryScreenRetinaScale2() {
        // primary screen (0,0,1728,1117), scale 2 (Retina)
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let screenCGFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let scaled = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: 2.0)
        XCTAssertEqual(scaled, CGRect(x: 200, y: 400, width: 800, height: 600))
    }

    func test_scaledRect_secondaryScreenWithNegativeOrigin() {
        // secondary screen (cg origin (-1920, 0)), scale 1
        let region = CGRect(x: -1500, y: 100, width: 200, height: 200)
        let screenCGFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let scaled = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: 1.0)
        XCTAssertEqual(scaled, CGRect(x: 420, y: 100, width: 200, height: 200))
    }

    func test_clampedRect_fullyInside() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 200)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertEqual(clamped, rect)
    }

    func test_clampedRect_partialOutsideClipsToImage() {
        let rect = CGRect(x: 900, y: 900, width: 200, height: 200)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertEqual(clamped, CGRect(x: 900, y: 900, width: 100, height: 100))
    }

    func test_clampedRect_completelyOutsideReturnsEmpty() {
        let rect = CGRect(x: 2000, y: 2000, width: 100, height: 100)
        let imageSize = CGSize(width: 1000, height: 1000)
        let clamped = CropMath.clampedRect(rect, imageSize: imageSize)
        XCTAssertTrue(clamped.isEmpty)
    }

    func test_imageScale_isImageWidthDividedByScreenWidth() {
        let scale = CropMath.imageScale(imageWidth: 3456, screenWidth: 1728)
        XCTAssertEqual(scale, 2.0)
    }
}
```

- [ ] **Step 3.2: テスト実行（失敗確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | grep -E "error|FAIL" | head
```

Expected: `Cannot find 'CropMath' in scope`

- [ ] **Step 3.3: 最小実装**

`Mas/Logic/CropMath.swift`:

```swift
import CoreGraphics

/// 画面キャプチャした全画面画像から region を切り出すための純粋計算。
enum CropMath {

    /// 物理ピクセル / 論理ポイントのスケール係数。
    static func imageScale(imageWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        guard screenWidth > 0 else { return 1.0 }
        return imageWidth / screenWidth
    }

    /// CG グローバル座標の region を、特定スクリーン画像内のピクセル座標に変換する。
    static func scaledRect(region: CGRect, screenCGFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (region.origin.x - screenCGFrame.origin.x) * scale,
            y: (region.origin.y - screenCGFrame.origin.y) * scale,
            width: region.width * scale,
            height: region.height * scale
        )
    }

    /// 画像範囲にクランプする（食み出し部分をカット）。
    static func clampedRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        rect.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
```

- [ ] **Step 3.4: テスト実行（成功確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 3.5: 既存呼び出しを CropMath 経由に置換**

`Mas/ViewModels/CaptureViewModel.swift` の `recaptureRegion` 内：

```swift
// 変更前
let imageWidth = CGFloat(fullScreenImage.width)
let imageHeight = CGFloat(fullScreenImage.height)
let scale = imageWidth / screen.frame.width

let screenCGFrame = screen.cgFrame
let scaledRect = CGRect(
    x: (region.origin.x - screenCGFrame.origin.x) * scale,
    y: (region.origin.y - screenCGFrame.origin.y) * scale,
    width: region.width * scale,
    height: region.height * scale
)

let clampedRect = scaledRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
```

```swift
// 変更後
let imageWidth = CGFloat(fullScreenImage.width)
let imageHeight = CGFloat(fullScreenImage.height)
let scale = CropMath.imageScale(imageWidth: imageWidth, screenWidth: screen.frame.width)

let screenCGFrame = screen.cgFrame
let scaledRect = CropMath.scaledRect(region: region, screenCGFrame: screenCGFrame, scale: scale)
let clampedRect = CropMath.clampedRect(scaledRect, imageSize: CGSize(width: imageWidth, height: imageHeight))
```

`Mas/Services/GifRecordingService.swift` と `Mas/Services/ShutterService.swift` にも同パターンの計算がある（spec 参照）。同じく置換する：

```bash
grep -n "region.origin.x - screenCGFrame.origin.x" Mas/Services/*.swift
```

該当箇所をすべて `CropMath.scaledRect` に置換。

- [ ] **Step 3.6: ビルド + テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 3.7: 手動動作確認**

```bash
xcodebuild -scheme ScreenshotApp -configuration Debug build 2>&1 | tail -3
killall -9 Mas 2>&1 || true; sleep 1
rm -rf /Applications/Mas.app
cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/
open /Applications/Mas.app
```

範囲選択キャプチャと再キャプチャが動くこと、GIF 録画も動くことを目視確認。

- [ ] **Step 3.8: Commit**

```bash
git add Mas/Logic/CropMath.swift MasTests/PureLogic/CropMathTests.swift Mas/ViewModels/CaptureViewModel.swift Mas/Services/GifRecordingService.swift Mas/Services/ShutterService.swift
git commit -m "refactor: crop 計算を CropMath に抽出してテスト追加"
```

---

## Task 4: CaptureRegionMath 抽出

**Files:**
- Create: `Mas/Logic/CaptureRegionMath.swift`
- Create: `MasTests/PureLogic/CaptureRegionMathTests.swift`
- Modify: `Mas/Views/EditorWindow.swift`

- [ ] **Step 4.1: 失敗するテストを書く**

`MasTests/PureLogic/CaptureRegionMathTests.swift`:

```swift
import XCTest
@testable import ScreenshotApp

final class CaptureRegionMathTests: XCTestCase {

    func test_windowFrameToCaptureRegion_convertsNSToCG() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
        let primaryHeight: CGFloat = 1117
        let region = CaptureRegionMath.windowFrameToCaptureRegion(nsFrame: frame, primaryHeight: primaryHeight)
        XCTAssertEqual(region, CGRect(x: 100, y: 517, width: 300, height: 400))
    }

    func test_clampedWindowFrame_fitsInsideScreen() {
        let proposed = CGRect(x: 100, y: 100, width: 500, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped, proposed)
    }

    func test_clampedWindowFrame_clipsToScreenWhenOversized() {
        let proposed = CGRect(x: 100, y: 100, width: 5000, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped.width, 1728)
        XCTAssertEqual(clamped.origin.x, 0)
    }

    func test_clampedWindowFrame_shiftsLeftWhenExceedsRightEdge() {
        // window が右にはみ出すケース
        let proposed = CGRect(x: 1500, y: 100, width: 500, height: 400)
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
        XCTAssertEqual(clamped.origin.x, 1228)  // 1728 - 500
        XCTAssertEqual(clamped.width, 500)
    }

    func test_initialContentScale_imageFitsInScreen() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 800, height: 600),
            screenVisibleSize: CGSize(width: 1728, height: 1117)
        )
        XCTAssertEqual(scale, 1.0)
    }

    func test_initialContentScale_imageWiderThanScreenScalesDown() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 3000, height: 600),
            screenVisibleSize: CGSize(width: 1500, height: 1117)
        )
        XCTAssertEqual(scale, 0.5)
    }

    func test_initialContentScale_imageTallerThanScreenScalesDown() {
        let scale = CaptureRegionMath.initialContentScale(
            contentSize: CGSize(width: 800, height: 2000),
            screenVisibleSize: CGSize(width: 1728, height: 1000)
        )
        XCTAssertEqual(scale, 0.5)
    }
}
```

- [ ] **Step 4.2: テスト実行（失敗確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | grep -E "error|FAIL" | head
```

Expected: `Cannot find 'CaptureRegionMath' in scope`

- [ ] **Step 4.3: 最小実装**

`Mas/Logic/CaptureRegionMath.swift`:

```swift
import CoreGraphics

/// キャプチャ枠ウィンドウに関する純粋計算。
/// `window.frame` ↔ CG region 変換、画面に収めるためのウィンドウサイズ調整、
/// コンテンツスケールの初期計算など。
enum CaptureRegionMath {

    /// NS 座標のウィンドウフレームを CG 座標のキャプチャ region に変換。
    static func windowFrameToCaptureRegion(nsFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CoordinateMath.nsToCG(nsFrame, primaryHeight: primaryHeight)
    }

    /// 提案されたウィンドウフレームを画面の可視領域内に収まるよう調整する。
    /// 元のサイズが画面より大きければ画面サイズに丸め、位置がはみ出していれば中央寄せ的に詰める。
    static func clampedWindowFrame(proposed: CGRect, screenVisibleFrame: CGRect) -> CGRect {
        let newWidth = min(proposed.width, screenVisibleFrame.width)
        let newHeight = min(proposed.height, screenVisibleFrame.height)
        let newX = max(
            screenVisibleFrame.minX,
            min(proposed.origin.x, screenVisibleFrame.maxX - newWidth)
        )
        let newY = max(
            screenVisibleFrame.minY,
            min(proposed.origin.y, screenVisibleFrame.maxY - newHeight)
        )
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    /// コンテンツが画面に収まるための初期スケール。1.0 を上限とする（拡大はしない）。
    static func initialContentScale(contentSize: CGSize, screenVisibleSize: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1.0 }
        let scaleX = screenVisibleSize.width / contentSize.width
        let scaleY = screenVisibleSize.height / contentSize.height
        return min(scaleX, scaleY, 1.0)
    }
}
```

- [ ] **Step 4.4: テスト実行（成功確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 4.5: 既存呼び出しを CaptureRegionMath 経由に置換**

`Mas/Views/EditorWindow.swift` の `getCurrentWindowRect`:

```swift
// 変更前
private func getCurrentWindowRect() -> CGRect {
    guard let window = parentWindow else {
        return screenshot.captureRegion ?? .zero
    }
    let frame = window.frame
    let primaryHeight = NSScreen.primaryScreenHeight
    let rect = CGRect(
        x: frame.origin.x,
        y: primaryHeight - frame.origin.y - frame.height,
        width: frame.width,
        height: frame.height
    )
    return rect
}
```

```swift
// 変更後
private func getCurrentWindowRect() -> CGRect {
    guard let window = parentWindow else {
        return screenshot.captureRegion ?? .zero
    }
    return CaptureRegionMath.windowFrameToCaptureRegion(
        nsFrame: window.frame,
        primaryHeight: NSScreen.primaryScreenHeight
    )
}
```

`setContentScale` 内のクランプ処理：

```swift
// 変更前（setContentScale 内）
let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
let newWidth = min(scaledWidth, screenFrame.width)
let newHeight = min(scaledHeight, screenFrame.height)
if newWidth != currentFrame.width || newHeight != currentFrame.height {
    let newX = max(screenFrame.minX, min(currentFrame.origin.x, screenFrame.maxX - newWidth))
    let newY = max(screenFrame.minY, min(currentFrame.origin.y + (currentFrame.height - newHeight), screenFrame.maxY - newHeight))
    window.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: true)
    ...
}
```

```swift
// 変更後
let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
let proposed = CGRect(
    x: currentFrame.origin.x,
    y: currentFrame.origin.y + (currentFrame.height - scaledHeight),
    width: scaledWidth,
    height: scaledHeight
)
let clamped = CaptureRegionMath.clampedWindowFrame(proposed: proposed, screenVisibleFrame: screenFrame)
if clamped.size != currentFrame.size {
    window.setFrame(clamped, display: true, animate: true)
    ...
}
```

`applyDroppedImage` 内の `setContentScale(fitScale)` 呼び出し前のスケール計算：

```swift
// 変更前
let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
let scaleX = screenFrame.width / newSize.width
let scaleY = screenFrame.height / newSize.height
let fitScale = min(scaleX, scaleY, 1.0)
setContentScale(fitScale)
```

```swift
// 変更後
let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
let fitScale = CaptureRegionMath.initialContentScale(
    contentSize: newSize,
    screenVisibleSize: screenFrame.size
)
setContentScale(fitScale)
```

`Mas/ViewModels/CaptureViewModel.swift` の `showEditorWindow` 内にも `initialContentScale` 計算がある。同様に置換：

```swift
// 変更前
let scaleX = screenFrame.width / contentWidth
let scaleY = screenFrame.height / contentHeight
let initialContentScale = min(scaleX, scaleY, 1.0)
```

```swift
// 変更後
let initialContentScale = CaptureRegionMath.initialContentScale(
    contentSize: CGSize(width: contentWidth, height: contentHeight),
    screenVisibleSize: screenFrame.size
)
```

- [ ] **Step 4.6: ビルド + テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 4.7: 手動動作確認**

範囲選択 → 移動 → 再キャプチャ → コンテンツサイズメニュー → ファイルドロップ画像差し替え、を一通り動作確認。

- [ ] **Step 4.8: Commit**

```bash
git add Mas/Logic/CaptureRegionMath.swift MasTests/PureLogic/CaptureRegionMathTests.swift Mas/Views/EditorWindow.swift Mas/ViewModels/CaptureViewModel.swift
git commit -m "refactor: window frame ↔ region 計算を CaptureRegionMath に抽出してテスト追加"
```

---

## Task 5: AnnotationGeometry 抽出

**Files:**
- Create: `Mas/Logic/AnnotationGeometry.swift`
- Create: `MasTests/PureLogic/AnnotationGeometryTests.swift`
- Modify: `Mas/Views/EditorWindow.swift` (`AnnotationCanvas.resizedRect`)

- [ ] **Step 5.1: 失敗するテストを書く**

`MasTests/PureLogic/AnnotationGeometryTests.swift`:

```swift
import XCTest
@testable import ScreenshotApp

final class AnnotationGeometryTests: XCTestCase {

    // ResizeHandle = topLeft でリサイズ
    func test_resizedRect_topLeft_movesOriginAndShrinksSize() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .topLeft, to: CGPoint(x: 150, y: 150))
        XCTAssertEqual(resized.origin.x, 150)
        XCTAssertEqual(resized.origin.y, 150)
        XCTAssertEqual(resized.width, 150)
        XCTAssertEqual(resized.height, 150)
    }

    func test_resizedRect_bottomRight_growsSizeOnly() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .bottomRight, to: CGPoint(x: 400, y: 400))
        XCTAssertEqual(resized.origin.x, 100)
        XCTAssertEqual(resized.origin.y, 100)
        XCTAssertEqual(resized.width, 300)
        XCTAssertEqual(resized.height, 300)
    }

    func test_resizedRect_top_changesYAndHeight() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let resized = AnnotationGeometry.resizedRect(original: original, handle: .top, to: CGPoint(x: 150, y: 50))
        XCTAssertEqual(resized.origin.x, 100)
        XCTAssertEqual(resized.origin.y, 50)
        XCTAssertEqual(resized.width, 200)
        XCTAssertEqual(resized.height, 250)
    }

    func test_squareConstrainedResizePoint_topLeftEqualSizes() {
        let original = CGRect(x: 100, y: 100, width: 200, height: 200)
        let constrained = AnnotationGeometry.squareConstrainedResizePoint(
            point: CGPoint(x: 50, y: 80),  // dx=-250, dy=-220 from anchor (300,300)
            original: original,
            handle: .topLeft
        )
        // anchor=(maxX=300, minY=100), dx=-250, dy=-20, max(|dx|,|dy|)=250
        // size 250, dx<0 dy<0 → result = (300-250, 100-250) = (50, -150)
        XCTAssertEqual(constrained.x, 50)
        XCTAssertEqual(constrained.y, -150)
    }

    func test_lineBoundingRect_includesBothEndpoints() {
        let rect = AnnotationGeometry.lineBoundingRect(
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 300, y: 50),
            lineWidth: 4
        )
        // 直線は両端を含み、線幅分パディング
        XCTAssertLessThanOrEqual(rect.minX, 100)
        XCTAssertLessThanOrEqual(rect.minY, 50)
        XCTAssertGreaterThanOrEqual(rect.maxX, 300)
        XCTAssertGreaterThanOrEqual(rect.maxY, 200)
    }
}
```

- [ ] **Step 5.2: テスト実行（失敗確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | grep -E "error|FAIL" | head
```

Expected: `Cannot find 'AnnotationGeometry' in scope`

- [ ] **Step 5.3: 最小実装**

既存の `EditorWindow.swift` の `AnnotationCanvas` クラス内にある `resizedRect` 関数と `squareConstrainedResizePoint` 関数を抽出する。先に Step 5.5 で対象コードを確認してから実装。

`Mas/Logic/AnnotationGeometry.swift`:

```swift
import CoreGraphics

enum ResizeHandle {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
}

/// アノテーション図形の純粋幾何計算。リサイズ後 rect・直線/矩形の bounding rect・
/// Shift 拘束時の対角アンカー計算など。
enum AnnotationGeometry {

    /// 既存矩形をリサイズハンドルとマウス座標から再計算する。
    static func resizedRect(original: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var newRect = original
        switch handle {
        case .topLeft:
            let newWidth = original.maxX - point.x
            let newHeight = original.maxY - point.y
            newRect = CGRect(x: point.x, y: point.y, width: newWidth, height: newHeight)
        case .topRight:
            let newWidth = point.x - original.minX
            let newHeight = original.maxY - point.y
            newRect = CGRect(x: original.minX, y: point.y, width: newWidth, height: newHeight)
        case .bottomLeft:
            let newWidth = original.maxX - point.x
            let newHeight = point.y - original.minY
            newRect = CGRect(x: point.x, y: original.minY, width: newWidth, height: newHeight)
        case .bottomRight:
            let newWidth = point.x - original.minX
            let newHeight = point.y - original.minY
            newRect = CGRect(x: original.minX, y: original.minY, width: newWidth, height: newHeight)
        case .top:
            newRect = CGRect(x: original.minX, y: point.y, width: original.width, height: original.maxY - point.y)
        case .bottom:
            newRect = CGRect(x: original.minX, y: original.minY, width: original.width, height: point.y - original.minY)
        case .left:
            newRect = CGRect(x: point.x, y: original.minY, width: original.maxX - point.x, height: original.height)
        case .right:
            newRect = CGRect(x: original.minX, y: original.minY, width: point.x - original.minX, height: original.height)
        }
        return newRect
    }

    /// Shift 押下時、対角アンカーを固定して正方形になるよう座標を補正する。
    static func squareConstrainedResizePoint(point: CGPoint, original: CGRect, handle: ResizeHandle) -> CGPoint {
        let anchor: CGPoint
        switch handle {
        case .topLeft:     anchor = CGPoint(x: original.maxX, y: original.minY)
        case .topRight:    anchor = CGPoint(x: original.minX, y: original.minY)
        case .bottomLeft:  anchor = CGPoint(x: original.maxX, y: original.maxY)
        case .bottomRight: anchor = CGPoint(x: original.minX, y: original.maxY)
        default: return point
        }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let size = max(abs(dx), abs(dy))
        return CGPoint(
            x: anchor.x + (dx >= 0 ? size : -size),
            y: anchor.y + (dy >= 0 ? size : -size)
        )
    }

    /// 直線の bounding rect。線幅分のパディングを含む。
    static func lineBoundingRect(startPoint: CGPoint, endPoint: CGPoint, lineWidth: CGFloat) -> CGRect {
        let pad = lineWidth / 2
        return CGRect(
            x: min(startPoint.x, endPoint.x) - pad,
            y: min(startPoint.y, endPoint.y) - pad,
            width: abs(endPoint.x - startPoint.x) + pad * 2,
            height: abs(endPoint.y - startPoint.y) + pad * 2
        )
    }
}
```

- [ ] **Step 5.4: テスト実行（成功確認）**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 5.5: 既存呼び出しを AnnotationGeometry 経由に置換**

`Mas/Views/EditorWindow.swift` の `AnnotationCanvas` クラス内：

```bash
grep -n "private func resizedRect\|private func squareConstrainedResizePoint\|enum ResizeHandle" Mas/Views/EditorWindow.swift
```

該当箇所を削除し、呼び出し箇所を `AnnotationGeometry.resizedRect(...)` / `AnnotationGeometry.squareConstrainedResizePoint(...)` に置換。`ResizeHandle` 型は `AnnotationGeometry` で定義したものを利用する（クラス内型は削除）。

`Mas/Models/Annotations/LineAnnotation.swift` の `boundingRect()`:

```swift
// 変更前
func boundingRect() -> CGRect {
    let pad = lineWidth / 2
    return CGRect(
        x: min(startPoint.x, endPoint.x) - pad,
        y: min(startPoint.y, endPoint.y) - pad,
        width: abs(endPoint.x - startPoint.x) + pad * 2,
        height: abs(endPoint.y - startPoint.y) + pad * 2
    )
}
```

```swift
// 変更後
func boundingRect() -> CGRect {
    AnnotationGeometry.lineBoundingRect(startPoint: startPoint, endPoint: endPoint, lineWidth: lineWidth)
}
```

ArrowAnnotation 等にも類似の `boundingRect()` 計算があれば同様に置換（spec の AnnotationGeometry 定義範囲内のもの）。

- [ ] **Step 5.6: ビルド + テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全テスト pass。

- [ ] **Step 5.7: 手動動作確認**

エディタで rectangle/ellipse/line/arrow アノテーションを描画→選択→ハンドルでリサイズ、Shift 押しながらリサイズで正方形化、を目視確認。

- [ ] **Step 5.8: Commit**

```bash
git add Mas/Logic/AnnotationGeometry.swift MasTests/PureLogic/AnnotationGeometryTests.swift Mas/Views/EditorWindow.swift Mas/Models/Annotations/
git commit -m "refactor: アノテーション幾何計算を AnnotationGeometry に抽出してテスト追加"
```

---

## Task 6: Mas/CLAUDE.md 更新

**Files:**
- Modify: `Mas/CLAUDE.md`

- [ ] **Step 6.1: テスト関連セクションを追加**

`Mas/CLAUDE.md` の末尾に以下を追加：

````markdown

## テスト

### 単体テスト
- テストターゲット: `MasTests`
- 実行: `xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test`
- 構造:
  - `MasTests/PureLogic/` — 純粋ロジック（座標変換、crop計算等）
  - `MasTests/Regression/` — 過去バグの再発防止（Phase 2 以降で追加）

### バグ修正時のルール【絶対厳守】
- バグ修正コミットには **対応する単体テストを必ず追加** すること
- 純粋ロジックで再現できるバグ → `PureLogic/` に追加
- タイミング/UI依存バグ → Adapter プロトコル化して `Regression/` に追加（Phase 2）
- テスト不可能と判断する場合は PR 説明に理由を明記
- 回帰バックログは `docs/superpowers/specs/regression-backlog.md` 参照（Phase 3 で運用開始）

### リリース前必須チェック
- リリーススキル (`release` / `minor-release` / `major-release`) は手順0で `xcodebuild test` を実行
- 失敗時はリリース中断
````

- [ ] **Step 6.2: Commit**

```bash
git add Mas/CLAUDE.md
git commit -m "docs: CLAUDE.md にテスト運用ルールを追加"
```

---

## Task 7: release 系スキル更新

**Files:**
- Modify: `~/.claude/skills/release/SKILL.md`
- Modify: `~/.claude/skills/minor-release/SKILL.md`
- Modify: `~/.claude/skills/major-release/SKILL.md`

注: これらは Mas リポジトリ外の個人グローバル設定。Mas のコミットには含まれない。

- [ ] **Step 7.1: release スキルに手順0を追加**

`~/.claude/skills/release/SKILL.md` の手順1の前に以下を挿入：

````markdown
### 0. 単体テスト実行（必須）

リリース前に必ず単体テストを実行する。失敗したらリリース中断、修正してから再開。

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -20
```

「Test Suite ... passed」を確認。失敗したテストがあれば原因を修正、必要なら回帰テストを追加してから再実行。
````

- [ ] **Step 7.2: minor-release / major-release も同様に更新**

`~/.claude/skills/minor-release/SKILL.md` と `~/.claude/skills/major-release/SKILL.md` の手順1の前に Step 7.1 と同じブロックを挿入する。

- [ ] **Step 7.3: スキル動作確認**

```bash
ls ~/.claude/skills/release/SKILL.md ~/.claude/skills/minor-release/SKILL.md ~/.claude/skills/major-release/SKILL.md
grep -A2 "### 0\." ~/.claude/skills/release/SKILL.md ~/.claude/skills/minor-release/SKILL.md ~/.claude/skills/major-release/SKILL.md
```

3 ファイル全てに「### 0. 単体テスト実行（必須）」が含まれることを確認。

注: スキルファイルは Mas リポジトリ外なので git commit 不要。

---

## Task 8: 全体動作確認 + リリースリハーサル

- [ ] **Step 8.1: 全テスト実行**

```bash
cd /Users/norifumi.okumura/Mas
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -30
```

Expected:
- `SmokeTests`、`CoordinateMathTests`、`CropMathTests`、`CaptureRegionMathTests`、`AnnotationGeometryTests` 全てが含まれること
- `** TEST SUCCEEDED **`
- 合計テスト数 30 ケース以上

- [ ] **Step 8.2: 手動 E2E 動作確認**

```bash
xcodebuild -scheme ScreenshotApp -configuration Debug build 2>&1 | tail -3
killall -9 Mas 2>&1 || true; sleep 1
rm -rf /Applications/Mas.app
cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/
open /Applications/Mas.app
```

確認シナリオ：
1. 範囲選択キャプチャ → 画像が正しく撮れる
2. 枠を移動 → 右上ボタンで再キャプチャ → 新位置の内容になる
3. annotation 描画 (arrow/rect/ellipse/line) → 表示される
4. annotation 選択 → リサイズハンドルで拡縮できる
5. Shift 押しながら rect/ellipse 描画 → 正方形/正円になる
6. Finder から画像をドラッグ → 枠に落として画像差し替えされる
7. コンテンツサイズメニュー → 50%/100%/150% で枠サイズ変わる

全部 OK なら Phase 1 完了。

- [ ] **Step 8.3: リリースのリハーサル（dry-run）**

実際のリリースは別途行う。ここでは「リリーススキル手順0が機能するか」だけ確認：

```bash
# release スキルの手順0コマンドを単独実行
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -20
```

`** TEST SUCCEEDED **` を確認。これが通る限り、次回のパッチリリース時に release スキルがテストを走らせ、失敗時はリリース中断するようになる。

- [ ] **Step 8.4: Phase 1 完了コメント**

このプランに沿って全タスク完了したことを示すため、以下を実行：

```bash
git log --oneline | head -10
```

直近 6〜8 コミットに以下が含まれることを確認：
- `test: MasTests ターゲット追加 + smoke test`
- `refactor: 座標変換を CoordinateMath に抽出してテスト追加`
- `refactor: crop 計算を CropMath に抽出してテスト追加`
- `refactor: window frame ↔ region 計算を CaptureRegionMath に抽出してテスト追加`
- `refactor: アノテーション幾何計算を AnnotationGeometry に抽出してテスト追加`
- `docs: CLAUDE.md にテスト運用ルールを追加`

---

## Self-Review

実装後にこのチェックリストを通す（ユーザーは Phase 1 完了報告時に確認すること）：

- [ ] Spec の Phase 1 要件を全て実装したか
  - [x] テストターゲット追加
  - [x] CoordinateMath 抽出 + テスト
  - [x] CropMath 抽出 + テスト
  - [x] CaptureRegionMath 抽出 + テスト
  - [x] AnnotationGeometry 抽出 + テスト
  - [x] CLAUDE.md 更新
  - [x] release 系スキル更新
- [ ] 既存挙動の回帰なし（手動 E2E 全パス）
- [ ] テスト数 30+ ケース
- [ ] `xcodebuild test` が CI なしでも安定して走る

## Phase 2 への引き継ぎ

Phase 1 完了後、以下を別 plan として作成する：

- `2026-MM-DD-unit-testing-phase2.md` (recapture 回帰テスト)
- `2026-MM-DD-unit-testing-phase3.md` (回帰バックログ運用開始)
