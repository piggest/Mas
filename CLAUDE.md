# Mas プロジェクトルール

## ビルド・リリース

### バージョン管理
- コードに変更を加える場合は、**必ず** `Mas/Info.plist` の `CFBundleVersion` と `CFBundleShortVersionString` を上げること
- リビジョン（3桁目）のみ自動で上げる（例: 1.6.2 → 1.6.3）
- マイナーバージョン（2桁目）はユーザーの明示的な指示があった場合のみ上げる

### ビルド確認
- ビルド確認時は、ビルド成果物を `/Applications/Mas.app` にコピーしてから起動すること
- 手順:
  1. `xcodebuild -scheme ScreenshotApp -configuration Debug build`
  2. 既存プロセスを終了: `pkill -x Mas`
  3. コピー: `cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/`
  4. 起動: `open /Applications/Mas.app`

### リリース時のHomebrew更新
- リリースでDMGをGitHub Releaseに添付した後、`piggest/homebrew-mas` のCaskも更新すること
- 更新対象: `mas.rb` と `Casks/mas.rb` の2ファイル
- 更新内容: `version` と `sha256`（DMGのハッシュ）、`url`のファイル名パターン
- sha256はリリースに添付したDMGをダウンロードして `shasum -a 256` で取得
- GitHub API経由で更新: `gh api repos/piggest/homebrew-mas/contents/<path> --method PUT ...`

## Git
- プッシュ前に `gh auth switch --user piggest` でアカウントを切り替えること

## テスト

### 単体テスト
- テストターゲット: `MasTests`
- 実行: `xcodebuild -scheme ScreenshotApp -destination 'platform=macOS' test`
- 構造:
  - `MasTests/PureLogic/` — 純粋ロジック（座標変換、crop計算、annotation幾何 等）
  - `MasTests/Regression/` — 過去バグの再発防止（Phase 2 以降で追加）
- ヘルパー: `GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb <path> <target>` でファイルを Xcode ターゲットに登録（`scripts/add-mastests-target.rb` で `MasTests` ターゲット自体の追加もできる）

### バグ修正時のルール【絶対厳守】
- バグ修正コミットには **対応する単体テストを必ず追加** すること
- 純粋ロジックで再現できるバグ → `MasTests/PureLogic/` に追加
- タイミング/UI依存バグ → Adapter プロトコル化して `MasTests/Regression/` に追加（Phase 2 で枠を作る）
- テスト不可能と判断する場合は PR 説明に理由を明記
- 回帰バックログは `docs/superpowers/specs/regression-backlog.md` 参照（Phase 3 で運用開始）

### リリース前必須チェック
- リリーススキル (`release` / `minor-release` / `major-release`) は手順0で `xcodebuild test` を実行
- 失敗時はリリース中断、修正してから再開
