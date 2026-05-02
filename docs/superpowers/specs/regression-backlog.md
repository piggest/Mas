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
| ✅ | `ed5a438` | Fix multi-screen support for capture, coordinate conversion, and GIF recording (v2.2.1) | `CoordinateMath`/`CropMath` の負 origin スクリーンテストでカバー（Phase 1） |
| 🟡 | `29d9f09` | Fix annotations not applied during drag & drop (v3.4.1) | `Screenshot.renderFinalImage()` を直接テスト。アノテーション焼き付けが正しく動くこと、はみ出し時のサイズ拡張を検証 |
| 🟡 | `a5f8325` | Fix crash caused by leaked didResizeNotification observer (v3.4.3) | observer リーク検出は XCTest だと困難。Instruments 推奨。Skip 寄りだが `XCTestExpectation` で deinit 到達確認パターンは可能 |

## Medium

| Status | Commit | Subject | Test Strategy |
|---|---|---|---|
| 🟡 | `1c65e0f` | Fix recapture not replacing GIF with new screenshot | recapture 時の `screenshot.savedURL = nil` で GIF mode 解除されることを検証。`RecaptureRegressionTests` 拡張で対応可能 |
| 🟡 | `4051449` | Fix clipboard copy to include annotations from context menu (v3.8.1) | `Screenshot.renderFinalImage` がアノテーションを含むことが Phase 3 Task 2 で検証される。Clipboard サービス側の DI が必要 |
| 🟡 | `df0940a` | Fix text selection mode: pass events to SwiftUI overlay and add Cmd+C support | テキスト選択モードのイベント伝搬。AnnotationGeometry / TextRecognition 周辺 |
| ⚪ | `c415eed` | Fix video/GIF default save path falling back to Desktop | UserDefaults / FileManager 依存。Adapter 化が必要だが工数大 |
| ⚪ | `fd5f7c5` | Fix programmable shutter panel content not visible due to hosting view size mismatch | UI レイアウト/SwiftUI 表示問題。Skip |
| ⚪ | `bb613b2` | Fix GIF recording memory issue: disk-based frame storage with ring buffer | パフォーマンス系。メモリプロファイル必要。Skip |
| ⚪ | `d29a4bb` | Fix annotation editing on library images: disable window drag during edit mode | UI 動作・状態管理。Skip |

## Low

| Status | Commit | Subject | Test Strategy |
|---|---|---|---|
| ⚪ | `598f44d` | Right-align settings labels and fix dark mode toolbar (v3.5.0) | UI レイアウト。視覚目視のみ。Skip |
| ⚪ | `2b07e76` | Add close button to annotation toolbar and fix toolbar/panel positioning (v2.4.3) | UI 配置。Skip |
| ⚪ | `55a04e1` | Fix DMG mount parsing and auto-install on update detection | 更新フロー。リリースプロセス系。Skip |
| ⚪ | `821b12b` | ツールバーグループメニューとメニューバー非表示の問題を修正 | UI 動作。Skip |
| ⚪ | `92e89ac` | ツールバーのツール切替遅延を修正 | パフォーマンス・タイミング。Skip |
| ⚪ | `ca3e4e8` | 編集モード終了時のアプリハングを修正 | タイミング・状態遷移。Adapter 化大変。Skip |
| ⚪ | `869f15c` | 設定ウィンドウがフローティングエディタウィンドウの背面に表示される問題を修正 | NSWindow level 管理。Skip |
| ⚪ | `5dd3cf7` | オーバーレイウィンドウのcanBecomeKeyを有効にして範囲選択のEscキー修正 | UI イベント。Skip |
| ⚪ | `441b694` | 開いているウィンドウ一覧にサムネイルプレビューを追加し、キャプチャクラッシュを修正 | クラッシュ修正。再現条件不明。Skip |

## 運用ルール

- **リリースのたびに 1〜2 件消化**: パッチ／マイナー／メジャーいずれでも、`Pending` のいずれかをテスト化してから commit する習慣
- **新規バグ修正には必ずテスト**: `CLAUDE.md` 記載の通り。修正コミットに同時にテストを追加する
- **完璧主義に陥らない**: 全部 Done にする必要はない。Skip でも記録だけ残す。視覚バグや外部依存はそのまま残してよい
- **Phase 4 以降の検討**: Adapter プロトコル化が必要なバグ（clipboard、file I/O、video frame extraction など）は別 Phase で扱う

## 優先度の判断基準

- **High**: ユーザーが明示的に再現確認したバグ、座標計算など Pure Logic で完結する重要ロジック、過去にリグレッションした箇所
- **Medium**: 内部ロジック・状態管理。Adapter 化やリファクタが必要だがテスト可能
- **Low**: テスト工数 > 価値、または視覚目視のみで気づくバグ
