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

## Git
- プッシュ前に `gh auth switch --user piggest` でアカウントを切り替えること
