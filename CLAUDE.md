# Mas プロジェクトルール

## ビルド・リリース

### バージョン管理
- コードに変更を加える場合は、**必ず** `Mas/Info.plist` の `CFBundleVersion` と `CFBundleShortVersionString` を上げること
- パッチレベル（例: 1.4.5 → 1.4.6）で上げる

### ビルド確認
- ビルド確認時は、ビルド成果物を `/Applications/Mas.app` にコピーしてから起動すること
- 手順:
  1. `xcodebuild -scheme ScreenshotApp -configuration Debug build`
  2. 既存プロセスを終了: `pkill -x Mas`
  3. コピー: `cp -R ~/Library/Developer/Xcode/DerivedData/Mas-*/Build/Products/Debug/Mas.app /Applications/`
  4. 起動: `open /Applications/Mas.app`

## Git
- プッシュ前に `gh auth switch --user piggest` でアカウントを切り替えること
