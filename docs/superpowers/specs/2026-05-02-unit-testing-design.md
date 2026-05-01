# 単体テスト導入設計

作成日: 2026-05-02
ステータス: 承認済み（実装計画作成中）

## 背景

直近のリリース（v3.6.6 → v4.2.x）で複数の回帰バグが発生した。代表例：

- v3.6.6 (`568c8bc`): 再キャプチャ時の `orderOut` 後 200ms sleep を「不要」と判断して削除した結果、`captureScreen` が呼ばれるタイミングと衝突して移動後の新位置の内容が反映されなくなった。発見まで数バージョンかかった。

これまで Mas には単体テストが一切存在せず、リグレッションが目視でしか検出できない状態だった。バグ修正のたびに対応するテストを書き、リリース時にチェックする仕組みを導入する。

## 目的

1. バグ修正したロジックを単体テストで守る（リグレッション再発防止）
2. リリース前に必ずテストを実行し、失敗時はリリースを中断する仕組みを CLAUDE.md と release 系スキルに組み込む
3. 過去のバグも段階的にテスト化していく

## アプローチ

段階導入（Approach A）：

- **Phase 1**: テストターゲット作成、純粋ロジック切り出し、切り出した分のテスト、リリーススキル更新
- **Phase 2**: `ScreenCapturing` / `WindowFrameProviding` / `SleepProviding` プロトコル化、今回の recapture バグ回帰テスト
- **Phase 3**: 過去バグの回帰テストを継続的に積み上げ（バグ発生・修正のたびに追加）

## アーキテクチャ

3層に整理する：

```
┌────────────────────────────────────────┐
│ View / ViewModel 層 (UI, AppKit依存)    │  ← 手動テスト
├────────────────────────────────────────┤
│ Adapter 層 (プロトコル定義)              │  ← Phase 2 でモック化テスト
│   ScreenCapturing, WindowFrameProvider │
├────────────────────────────────────────┤
│ Pure Logic 層 (純粋関数 / 値型)          │  ← Phase 1 でテスト
│   CoordinateMath, CropMath,            │
│   CaptureRegionMath, AnnotationGeometry│
└────────────────────────────────────────┘
```

- **Pure Logic 層**: AppKit/Foundation の値型（`CGRect`, `CGFloat`, `NSSize`）しか使わない純粋関数群。Phase 1 で抽出。
- **Adapter 層**: AppKit に依存する API（画面キャプチャ、`NSWindow.frame` 取得、`Task.sleep`）をプロトコルで包む。Phase 2 で導入。本番は実装、テストは Mock。
- **View/ViewModel 層**: SwiftUI/AppKit と直接対話。テスト不要。Adapter と Pure Logic を組み合わせて UI ロジックを実現。

## テストターゲット構成

Xcode プロジェクトに `MasTests` ターゲット追加（`@testable import ScreenshotApp`）。

```
Mas.xcodeproj
├─ ScreenshotApp (既存・本番)
└─ MasTests (新規・XCTest)
```

- フレームワークは **XCTest**（macOS 13+ 対応・標準・既存資料豊富）。Swift Testing は macOS 14+ 必須なので Mas の deployment target 13.0 と合わない。
- ターゲット追加は **`project.pbxproj` を直接編集**（差分が分かりやすく Claude が再現できる）。
- 実行コマンド: `xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test`

## Phase 1 詳細

### 抽出対象

| 切り出し先 | 内容 | 元ソース |
|---|---|---|
| `Mas/Logic/CoordinateMath.swift` | NS↔CG 変換、`screen.cgFrame` の純粋計算 | `Services/ScreenCaptureService.swift` の extension |
| `Mas/Logic/CropMath.swift` | `region` → `scaledRect` → `clampedRect` 計算 | `recaptureRegion` 内のロジック |
| `Mas/Logic/CaptureRegionMath.swift` | window frame → CGRect 変換、resize時の origin/size 計算 | `getCurrentWindowRect`, `setContentScale`, トリミング座標計算 |
| `Mas/Logic/AnnotationGeometry.swift` | annotation の `boundingRect`, hitTest, リサイズ後 rect 計算 | `Annotation` 各実装、`AnnotationCanvas.resizedRect` |

### 切り出しの形

static メソッドの enum（インスタンス化させない）。

```swift
enum CoordinateMath {
    static func nsToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect { ... }
    static func cgToNS(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect { ... }
}

enum CropMath {
    static func scaledRect(region: CGRect, screenCGFrame: CGRect, scale: CGFloat) -> CGRect { ... }
    static func clampedRect(_ rect: CGRect, imageSize: CGSize) -> CGRect { ... }
}
```

### Phase 1 で書くテスト

各ファイル 5〜10 ケース、合計 30〜40 ケース。代表ケース：

- 単一スクリーン原点 (0,0) での NS↔CG 変換が対称
- マルチスクリーンで負座標を含むスクリーンの変換
- Retina スケール 2.0 での scaledRect 計算
- region がスクリーン端から食み出る場合の clamped 結果
- annotation の boundingRect が回転/反転に対応

### 既存呼び出しの差し替え

抽出後、`recaptureRegion`・`getCurrentWindowRect`・`setContentScale` 等は `CoordinateMath`・`CropMath` を呼ぶ薄いラッパに置き換える（挙動同等）。

## Phase 2 詳細

### プロトコル抽出

```swift
// Mas/Adapters/ScreenCapturing.swift
protocol ScreenCapturing {
    func captureScreen(_ screen: NSScreen) async throws -> CGImage
}
extension ScreenCaptureService: ScreenCapturing {}

// Mas/Adapters/WindowFrameProviding.swift
protocol WindowFrameProviding: AnyObject {
    var frame: NSRect { get }
    var screen: NSScreen? { get }
}
extension NSWindow: WindowFrameProviding {}

// Mas/Adapters/SleepProviding.swift
protocol SleepProviding {
    func sleep(nanoseconds: UInt64) async
}
struct RealSleeper: SleepProviding {
    func sleep(nanoseconds ns: UInt64) async { try? await Task.sleep(nanoseconds: ns) }
}
```

### `RecaptureFlow` 切り出し

`CaptureViewModel.recaptureRegion` から、テスト可能なロジック部分を関数に切り出す：

```swift
// Mas/Logic/RecaptureFlow.swift
struct RecaptureFlow {
    let capturer: ScreenCapturing
    let sleeper: SleepProviding

    func run(region: CGRect, isDevMode: Bool, hideWindow: () -> Void, showWindow: () -> Void) async throws -> (image: CGImage, region: CGRect)
}
```

実本番の `CaptureViewModel.recaptureRegion` はこの `RecaptureFlow.run` を呼んで結果を `screenshot.updateImage` / `captureRegion` に書き込む薄いラッパに。

### Phase 2 で書く回帰テスト

`MasTests/Regression/RecaptureRegressionTests.swift`：

| テスト | バグ |
|---|---|
| `test_recaptureUsesCurrentWindowFrameNotCachedRegion` | 今回の本丸：移動後 region が `window.frame` 由来であること |
| `test_devModeOrderOutsAndSleeps200ms` | 開発モード時のみ orderOut + sleep |
| `test_normalModeSkipsOrderOutAndSleep` | 通常モードは即時実行 |
| `test_emptyClampedRegionReturnsEarlyWithoutUpdate` | scaledRect が画像範囲外で空のとき安全に early return |
| `test_capturedImageReplacesScreenshotImage` | `screenshot.updateImage` が呼ばれて新画像が反映 |

`MockScreenCapturing` は事前に「特定 region で呼ばれたら特定 CGImage を返す」契約を持ち、テスト側で region 検証。`MockSleeper` は呼ばれた回数とトータル ns を記録。

## Phase 3 詳細

### 運用ルール（CLAUDE.md に記載）

> バグ修正コミット時は対応する単体テストを必ず追加する
> - 純粋ロジックで再現できるバグ → `Logic/*Tests` に追加
> - タイミング/UI依存バグ → `Regression/*RegressionTests` に Mock 利用で追加
> - 「テスト書きづらい」と感じたら、まず Adapter プロトコル化を検討
> - 例外的にテスト不可能なバグは PR 説明に理由を明記

### 過去バグ棚卸し

`docs/superpowers/specs/regression-backlog.md` を作成し、git log から「Fix」「修正」「バグ」コミットを拾って一覧化：

```markdown
# 回帰テスト Backlog

## 優先度 High
- [ ] v3.6.6 568c8bc 再キャプチャ後の sleep 削除回帰 → Phase 2 で対応済み
- [ ] v3.9.2 87bdbcd frame mode recording region offset (primaryScreenHeight) → CoordinateMath テストで対応
- [ ] v3.6.5 e5bcda9 window tap capture coordinate conversion → CoordinateMath テストで対応

## 優先度 Medium
- [ ] v3.4.1 29d9f09 annotations not applied during drag & drop
- [ ] v3.4.3 a5f8325 didResizeNotification observer leak
- [ ] v3.7.x video trim edge case
```

リリースの度に backlog を 1〜2 件消化することを CLAUDE.md に明記。完璧主義に陥らず、できる範囲で積み上げる方針。

### 判定不能なもの

UI 配置・色・位置調整など視覚目視のみで分かるバグはテスト対象外。Backlog に記載しないか、`out-of-scope` セクションへ。

## リリーススキル / CLAUDE.md 改訂

### `~/.claude/skills/release/SKILL.md` 改訂（minor / major も同様）

手順1 の「現在のバージョン確認」の前に手順0として追加：

````markdown
### 0. 単体テスト実行（必須）

リリース前に必ず単体テストを実行する。失敗したらリリース中断、修正してから再開。

```bash
xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test 2>&1 | tail -20
```

「Test Suite ... passed」を確認。失敗したテストがあれば原因を修正、必要なら回帰テストを追加してから再実行。
````

### `/Users/norifumi.okumura/Mas/CLAUDE.md` 追加セクション

```markdown
## テスト

### 単体テスト
- テストターゲット: `MasTests`
- 実行: `xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test`
- 構造:
  - `MasTests/PureLogic/` — 純粋ロジック（座標変換、crop計算等）
  - `MasTests/Regression/` — 過去バグの再発防止（Mock使用）

### バグ修正時のルール【絶対厳守】
- バグ修正コミットには **対応する単体テストを必ず追加** すること
- 純粋ロジックで再現できるバグ → `PureLogic/` に追加
- タイミング/UI依存バグ → Adapter プロトコル化して `Regression/` に追加
- テスト不可能と判断する場合は PR 説明に理由を明記
- 回帰バックログは `docs/superpowers/specs/regression-backlog.md` 参照

### リリース前必須チェック
- リリーススキル (release / minor-release / major-release) は手順0で `xcodebuild test` を実行
- 失敗時はリリース中断
```

## ファイル構成（最終形）

```
Mas/
├── Mas/
│   ├── Logic/                          ← 新規・純粋ロジック層
│   │   ├── CoordinateMath.swift
│   │   ├── CropMath.swift
│   │   ├── CaptureRegionMath.swift
│   │   ├── AnnotationGeometry.swift
│   │   └── RecaptureFlow.swift         ← Phase 2
│   ├── Adapters/                       ← 新規・プロトコル層 (Phase 2)
│   │   ├── ScreenCapturing.swift
│   │   ├── WindowFrameProviding.swift
│   │   └── SleepProviding.swift
│   ├── ViewModels/CaptureViewModel.swift   ← recaptureRegion を薄く書き換え
│   ├── Services/ScreenCaptureService.swift ← ScreenCapturing 準拠
│   └── ...（既存）
├── MasTests/                           ← 新規・テストターゲット
│   ├── PureLogic/
│   │   ├── CoordinateMathTests.swift
│   │   ├── CropMathTests.swift
│   │   ├── CaptureRegionMathTests.swift
│   │   └── AnnotationGeometryTests.swift
│   ├── Regression/                     ← Phase 2
│   │   └── RecaptureRegressionTests.swift
│   └── Mocks/                          ← Phase 2
│       ├── MockScreenCapturing.swift
│       ├── MockWindowFrameProviding.swift
│       └── MockSleeper.swift
├── docs/
│   └── superpowers/
│       └── specs/
│           ├── 2026-05-02-unit-testing-design.md   ← この設計
│           └── regression-backlog.md               ← Phase 3
└── Mas.xcodeproj/project.pbxproj      ← MasTests ターゲット追加
```

## 成功基準

- Phase 1 完了時: `xcodebuild test` が成功し、純粋ロジックが 30〜40 ケースカバーされる。release 系スキルがテスト失敗時にリリース中断する。
- Phase 2 完了時: 今回の recapture バグを再現する回帰テストが書かれ、Mock パターンの雛形が確立される。
- Phase 3 継続: バグ修正のたびにテストが追加される運用が定着し、回帰バックログが消化されていく。

## 出典

このドキュメントは brainstorming セッション（2026-05-02）で承認された内容を反映している。
