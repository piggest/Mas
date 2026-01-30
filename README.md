# Mas - macOS スクリーンショットアプリ

> まるでマスですくうように簡単に正確にスクリーンショットを作成します

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.8-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## 概要

Mas（Mac Area Screenshot）は、macOS向けのネイティブスクリーンショットアプリケーションです。メニューバーに常駐し、グローバルホットキーで素早くスクリーンショットを撮影できます。撮影後は編集ウィンドウが自動的に表示され、矢印やテキストなどの注釈を追加できます。

## 特徴

- **メニューバー常駐**: Dockに表示されず、メニューバーから操作
- **グローバルホットキー**: 他のアプリを使用中でも素早くキャプチャ
- **3つのキャプチャモード**: 全画面、範囲選択、ウィンドウ
- **豊富な編集ツール**: 矢印、四角、丸、テキスト、ハイライト、モザイク
- **自動保存**: クリップボードへのコピーとファイル保存を自動実行
- **Retina対応**: 高解像度ディスプレイに完全対応

## システム要件

- macOS 13.0（Ventura）以上
- 画面収録の権限（初回起動時に許可が必要）

## インストール

### ビルド方法

```bash
git clone https://github.com/piggest/Mas.git
cd Mas
xcodebuild -scheme ScreenshotApp -configuration Release build
```

ビルド後、`DerivedData`内の`Mas.app`を`/Applications`フォルダにコピーしてください。

## 使い方

### キャプチャモード

| モード | ショートカット | 説明 |
|--------|---------------|------|
| 全画面 | `⌘⇧3` | メインディスプレイ全体をキャプチャ |
| 範囲選択 | `⌘⇧4` | マウスドラッグで選択した範囲をキャプチャ |
| ウィンドウ | `⌘⇧5` | 特定のウィンドウをキャプチャ |

### 範囲選択モード

1. `⌘⇧4`を押すと画面全体にオーバーレイが表示されます
2. マウスをドラッグして範囲を選択
3. マウスを離すとキャプチャが実行されます
4. `ESC`キーでキャンセル

### 編集機能

キャプチャ後、編集ウィンドウが表示されます。

1. **編集モードの開始**: 左下の鉛筆アイコンをクリック
2. **ツールボックス**: 別ウィンドウでツール選択画面が表示されます

#### 利用可能なツール

| ツール | アイコン | 説明 |
|--------|---------|------|
| 矢印 | ↗ | 矢印を描画 |
| 四角 | □ | 矩形を描画 |
| 丸 | ○ | 円・楕円を描画 |
| テキスト | T | テキストを挿入 |

#### 編集オプション

- **色の選択**: 6色のプリセットから選択（赤、青、緑、黄、黒、白）
- **サイズ調整**: スライダーで線幅を1〜10の範囲で調整
- **取消**: 最後の操作を取り消し

### エディタウィンドウの操作

- **ダブルクリック**: 画像を非表示にして枠のみ表示
- **再キャプチャ**: 右上のカメラアイコンで同じ範囲を再キャプチャ
- **ドラッグ&ドロップ**: 右下のアイコンからファイルとしてドラッグ可能
- **右クリック**: コンテキストメニューを表示

## 設定

メニューバーアイコンから「設定」を選択、または `⌘,` で設定画面を開けます。

### 一般設定

| 設定項目 | デフォルト | 説明 |
|---------|-----------|------|
| クリップボードに自動コピー | ON | キャプチャ時に自動でクリップボードにコピー |
| ファイルを自動保存 | ON | キャプチャ時に自動でファイルに保存 |
| 保存先フォルダ | ~/Pictures/Mas | 自動保存時の保存先 |
| デフォルト保存形式 | PNG | PNG または JPEG |
| JPEG品質 | 90% | JPEG保存時の圧縮品質 |

### ショートカット

現在、ショートカットキーは固定されています。

| 機能 | ショートカット |
|-----|---------------|
| 全画面キャプチャ | `⌘⇧3` |
| 範囲選択 | `⌘⇧4` |
| ウィンドウキャプチャ | `⌘⇧5` |
| 設定を開く | `⌘,` |
| 終了 | `⌘Q` |

## プロジェクト構成

```
Mas/
├── App/
│   ├── AppDelegate.swift         # アプリケーション初期化
│   └── HotkeyManager.swift       # グローバルホットキー管理
│
├── Models/
│   ├── CaptureMode.swift         # キャプチャモード定義
│   ├── Screenshot.swift          # スクリーンショットデータモデル
│   └── Annotations/              # 注釈クラス群
│       ├── Annotation.swift
│       ├── ArrowAnnotation.swift
│       ├── EllipseAnnotation.swift
│       ├── HighlightAnnotation.swift
│       ├── MosaicAnnotation.swift
│       ├── RectAnnotation.swift
│       └── TextAnnotation.swift
│
├── Services/
│   ├── ClipboardService.swift    # クリップボード操作
│   ├── FileStorageService.swift  # ファイル保存
│   ├── PermissionService.swift   # 権限管理
│   └── ScreenCaptureService.swift # 画面キャプチャ
│
├── ViewModels/
│   ├── CaptureViewModel.swift    # キャプチャ状態管理
│   └── EditorViewModel.swift     # 編集状態管理
│
├── Views/
│   ├── CanvasView.swift          # 描画キャンバス
│   ├── CaptureFlashView.swift    # キャプチャ時のフラッシュ
│   ├── EditorWindow.swift        # 編集ウィンドウ
│   ├── MenuBarView.swift         # メニューバーUI
│   ├── RegionSelectionOverlay.swift # 範囲選択オーバーレイ
│   ├── ResizableWindow.swift     # リサイズ可能ウィンドウ
│   ├── SettingsWindow.swift      # 設定画面
│   ├── ToolboxWindow.swift       # 編集ツールボックス
│   └── WindowPickerView.swift    # ウィンドウ選択UI
│
├── ScreenshotApp.swift           # メインエントリーポイント
└── Info.plist                    # アプリケーション設定
```

## 技術スタック

| 技術 | 用途 |
|-----|------|
| SwiftUI | UI構築 |
| AppKit | ネイティブウィンドウ管理 |
| CoreGraphics | 画像処理・座標計算 |
| CoreImage | モザイク効果（CIPixellate） |
| Carbon HIToolbox | グローバルホットキー |

## 開発

### 要件

- Xcode 14.3以上
- macOS 13.0以上

### ビルド

```bash
# Debug ビルド
xcodebuild -scheme ScreenshotApp -configuration Debug build

# Release ビルド
xcodebuild -scheme ScreenshotApp -configuration Release build
```

### 権限

アプリケーションは以下の権限を必要とします：

- **画面収録**: スクリーンショットの撮影に必要
  - システム設定 → プライバシーとセキュリティ → 画面収録 で許可

## コントリビューション

バグ報告や機能リクエストは [Issues](https://github.com/piggest/Mas/issues) でお願いします。

## 作者

piggest
