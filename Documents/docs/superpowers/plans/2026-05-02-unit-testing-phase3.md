# 単体テスト導入 Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 過去バグを棚卸しした `regression-backlog.md` を作成し、高優先度のバグ 2 件の回帰テストを追加して継続運用フェーズに移行する。

**Architecture:** Phase 1, 2 で確立した Pure Logic 層 + Adapter プロトコル層 + Mock の基盤を使って、git log から拾った過去のバグ修正コミットに対応するテストを追加する。バックログは `docs/superpowers/specs/regression-backlog.md` に集約し、リリースのたびに 1〜2 件消化する運用に乗せる。

**Tech Stack:** Markdown、XCTest、既存ヘルパー（`scripts/add-source-file.rb`）

---

## File Structure

### 新規作成

```
docs/superpowers/specs/
└── regression-backlog.md       ← Task 1

MasTests/Regression/
├── CoordinateRegressionTests.swift   ← Task 2
└── (残りは Phase 3 後続で追加)
```

---

## Task 1: regression-backlog.md 作成

**Files:**
- Create: `docs/superpowers/specs/regression-backlog.md`

git log から「Fix」「修正」「バグ」「fix」を含むコミットを抽出し、テスト化可能性で分類する。

- [ ] **Step 1.1: 過去のバグ修正コミット抽出**

```bash
cd /Users/norifumi.okumura/Mas
git log --oneline --grep="Fix\|fix\|修正\|バグ\|crash" | head -40
```

得られた一覧を「テスト化済み・テスト化候補・テスト化不要」に分類する。Phase 1 / 2 で既にカバーした分は「カバー済み」と明記。

- [ ] **Step 1.2: regression-backlog.md を作成**

`docs/superpowers/specs/regression-backlog.md`:

````markdown
# 回帰テスト Backlog

過去のバグ修正コミットを棚卸しした一覧。リリースのたびに 1〜2 件消化することを目標とする。

## ステータス

- ✅ **Done**: 既に対応する単体テストあり
- 🟡 **Pending**: テスト化可能、未対応
- ⚪ **Skip**: テスト化不可能/不要（UI レイアウト等の視覚バグ、外部 API 依存等）

## High（次回優先）

| Status | Commit | Subject | Test Strategy |
|---|---|---|---|
| ✅ | `568c8bc` | Remove unnecessary sleep delays in capture | `RecaptureRegressionTests` でカバー（Phase 2） |
| ✅ | `87bdbcd` | Fix frame mode recording region offset by using primaryScreenHeight | `CoordinateMathTests` の `nsToCG`/`cgFrameForScreen` でカバー（Phase 1） |
| ✅ | `e5bcda9` | Fix window tap capture in region selection: coordinate conversion | `CoordinateMathTests` でカバー（Phase 1） |
| 🟡 | `29d9f09` | Fix annotations not applied during drag & drop | アノテーション保存 → 再描画フローを純粋化して、保存→読み込みで状態が一致することをテスト。RectAnnotation などの `boundingRect()` ベース |
| 🟡 | `a5f8325` | Fix crash caused by leaked didResizeNotification observer | observer ライフサイクル系。`weak self` 漏れチェックは XCTest だと困難、Instruments 推奨。Skip 候補だが、別途 deinit の到達を `XCTestExpectation` で確認するパターンは可能 |

## Medium

| Status | Commit | Subject | Test Strategy |
|---|---|---|---|
| 🟡 | `e2adc29` | Expand image to include overflowing annotations on save/copy | `Screenshot.renderFinalImage()` 内の expandedRect 計算が AnnotationGeometry 化できれば純粋テスト可 |
| 🟡 | `c2f3136` | Auto-expand editor window when annotations overflow | アノテーションのはみ出し検知ロジック |
| ⚪ | `f72af7c` | 編集モード終了時のクラッシュ修正とアノテーションのドラッグ画像反映 | クラッシュ修正・タイミング依存。Skip |
| ⚪ | `886c385` | Fix multi-window state independence and button click issues | UI 状態管理。Skip |

## Low

| Status | Commit | Subject | Test Strategy |
|---|---|---|---|
| ⚪ | `4051449` | Fix clipboard copy to include annotations from context menu | Clipboard service 系。pasteboard モック化で可能だが Phase 4 以降 |
| ⚪ | `d29a4bb` | Fix annotation editing on library images: disable window drag during edit mode | UI 動作。Skip |

## 運用ルール

- **リリースのたびに 1〜2 件消化**: パッチ／マイナー／メジャーいずれでも、`Pending` のいずれかをテスト化してから commit する習慣
- **新規バグ修正には必ずテスト**: `CLAUDE.md` 記載の通り。修正コミットに同時にテストを追加する
- **完璧主義に陥らない**: 全部 Done にする必要はない。Skip でも記録だけ残す。視覚バグや外部依存はそのまま残してよい
- **Phase 4 以降の検討**: Adapter プロトコル化が必要なバグ（clipboard、file I/O、video frame extraction など）は別 Phase で扱う

## 優先度の判断基準

- **High**: ユーザーが明示的に再現確認したバグ、座標計算など Pure Logic で完結する重要ロジック
- **Medium**: 内部ロジック・状態管理。Adapter 化やリファクタが必要だがテスト可能
- **Low**: テスト工数 > 価値、または視覚目視のみで気づくバグ

````

- [ ] **Step 1.3: Commit**

```bash
cd /Users/norifumi.okumura/Mas
git add docs/superpowers/specs/regression-backlog.md
git commit -m "$(cat <<'EOF'
docs: 回帰テスト Backlog を作成

過去の Fix コミットを棚卸し、Done/Pending/Skip でステータス管理。
リリースのたびに 1〜2 件消化する運用ルールを明記。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 「Fix annotations not applied during drag & drop」回帰テスト

**Files:**
- Create: `MasTests/Regression/AnnotationDragDropRegressionTests.swift`

29d9f09 のバグ：annotation を描画した後、ドラッグ&ドロップでアプリ外に画像をコピーしたとき、アノテーションが反映されずに元画像のまま出力される問題。

このバグは `Screenshot.renderFinalImage()` がアノテーションを画像に焼き付けるロジックが、特定パスで呼ばれていなかったのが原因。

直接 `renderFinalImage()` をテストすることで、アノテーション付き画像が正しくレンダリングされていることを検証する。

- [ ] **Step 2.1: 既存 `Screenshot.renderFinalImage()` を確認**

```bash
cd /Users/norifumi.okumura/Mas
grep -n "func renderFinalImage" Mas/Models/Screenshot.swift
```

確認後、Read ツールで対象行を読む。

- [ ] **Step 2.2: テスト作成**

`MasTests/Regression/AnnotationDragDropRegressionTests.swift`:

```swift
import XCTest
import AppKit
@testable import Mas

/// 29d9f09 「Fix annotations not applied during drag & drop」回帰テスト。
/// renderFinalImage() がアノテーションを正しく焼き付けることを検証する。
final class AnnotationDragDropRegressionTests: XCTestCase {

    /// テスト用の単色 NSImage を作る。
    private func makeStubImage(width: Int, height: Int, color: NSColor = .white) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    func test_renderFinalImage_withoutAnnotations_returnsOriginalSize() {
        let image = makeStubImage(width: 200, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        let final = screenshot.renderFinalImage()
        XCTAssertEqual(final.size.width, 200, accuracy: 0.5)
        XCTAssertEqual(final.size.height, 100, accuracy: 0.5)
    }

    func test_renderFinalImage_withAnnotationInsideBounds_keepsOriginalSize() {
        let image = makeStubImage(width: 400, height: 300)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        // 画像内に収まる矩形アノテーションを追加
        let rectAnnotation = RectAnnotation(
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            color: .red,
            lineWidth: 3
        )
        screenshot.annotations = [rectAnnotation]

        let final = screenshot.renderFinalImage()
        // アノテーションが画像内なら、最終サイズは元と同じ
        XCTAssertEqual(final.size.width, 400, accuracy: 0.5)
        XCTAssertEqual(final.size.height, 300, accuracy: 0.5)
    }

    func test_renderFinalImage_withAnnotationOverflowingBounds_expandsImage() {
        let image = makeStubImage(width: 100, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        // 画像外に大きくはみ出す矩形アノテーション
        let rectAnnotation = RectAnnotation(
            rect: CGRect(x: -50, y: -50, width: 300, height: 300),
            color: .red,
            lineWidth: 3
        )
        screenshot.annotations = [rectAnnotation]

        let final = screenshot.renderFinalImage()
        // アノテーションがはみ出した分だけ画像サイズが拡張される
        XCTAssertGreaterThan(final.size.width, 100)
        XCTAssertGreaterThan(final.size.height, 100)
    }

    func test_renderFinalImage_returnsNonEmptyImage() {
        let image = makeStubImage(width: 200, height: 100)
        let screenshot = Screenshot(image: image, mode: .region, region: nil)

        let final = screenshot.renderFinalImage()
        // 戻り値が valid な画像であること（size が 0 でない）
        XCTAssertGreaterThan(final.size.width, 0)
        XCTAssertGreaterThan(final.size.height, 0)
    }
}
```

- [ ] **Step 2.3: ヘルパーで登録**

```bash
GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb MasTests/Regression/AnnotationDragDropRegressionTests.swift MasTests
```

- [ ] **Step 2.4: テスト実行**

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 全 43 tests pass（既存 39 + 新規 4）。

- [ ] **Step 2.5: Commit**

```bash
cd /Users/norifumi.okumura/Mas
git add MasTests/Regression/AnnotationDragDropRegressionTests.swift Mas.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
test: 29d9f09 アノテーションがドラッグ&ドロップで反映されないバグの回帰テスト

renderFinalImage() の動作を直接検証:
- アノテーションなし: 元サイズ維持
- 画像内アノテーション: 元サイズ維持
- はみ出しアノテーション: 画像サイズが拡張される
- 戻り値が非空

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

`regression-backlog.md` の `29d9f09` のステータスを `🟡` → `✅` に更新（Step 1.2 で書いた表を Edit）。

```bash
# Status の更新
git add docs/superpowers/specs/regression-backlog.md
git commit -m "docs: backlog 29d9f09 を Done に更新"
```

---

## Task 3: 動作確認 + Phase 3 完了

- [ ] **Step 3.1: 全テスト実行**

```bash
cd /Users/norifumi.okumura/Mas
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite '[A-Za-z]|Executed.*tests|TEST" | tail -15
```

Expected: 全 43 tests pass、`** TEST SUCCEEDED **`。

- [ ] **Step 3.2: コミット履歴確認**

```bash
git log --oneline main..HEAD
```

Phase 3 の commit が以下の流れで並ぶ：
- `docs: 回帰テスト Backlog を作成`
- `test: 29d9f09 アノテーションがドラッグ&ドロップで反映されないバグの回帰テスト`
- `docs: backlog 29d9f09 を Done に更新`

- [ ] **Step 3.3: PR 作成**

ユーザに確認後、piggest アカウントで PR 作成。マージはユーザの明示的指示を待つ。

---

## Self-Review

完了報告時：

- [ ] Phase 3 spec 要件カバー：
  - [x] `regression-backlog.md` 作成
  - [x] 過去バグの分類（Done/Pending/Skip）
  - [x] 高優先度 1 件以上の回帰テスト追加
  - [x] 運用ルール明記
- [ ] 既存挙動の回帰なし
- [ ] テスト数 43 ケース以上

## Phase 4 以降への引き継ぎ

- Backlog の Pending 項目を継続的にテスト化
- 必要に応じて Adapter プロトコル追加（Clipboard、FileStorage、AVFoundation 等）
- 視覚バグ用の Snapshot Test 導入は別途検討
