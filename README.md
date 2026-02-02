<p align="center">
  <img src="docs/appicon.png" alt="Mas App Icon" width="128" height="128">
</p>

# Mas - macOS スクリーンショットアプリ

> まるでマスですくうように簡単に正確にスクリーンショットを作成します

![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.8-orange.svg)
[![Download](https://img.shields.io/github/v/release/piggest/Mas?label=Download)](https://github.com/piggest/Mas/releases/latest)

## 概要

Mas（Mac Area Screenshot）は、macOS向けのネイティブスクリーンショットアプリケーションです。メニューバーに常駐し、グローバルホットキーで素早くスクリーンショットを撮影できます。撮影後は編集ウィンドウが自動的に表示され、矢印やテキストなどの注釈を追加できます。

## 特徴

- **メニューバー常駐**: Dockに表示されず、メニューバーから操作
- **グローバルホットキー**: 他のアプリを使用中でも素早くキャプチャ
- **3つのキャプチャモード**: 全画面、範囲選択、ウィンドウ
- **豊富な編集ツール**: ペン、マーカー、矢印、四角、丸、テキスト、モザイク
- **自動保存**: クリップボードへのコピーとファイル保存を自動実行
- **Retina対応**: 高解像度ディスプレイに完全対応

## システム要件

- macOS 13.0（Ventura）以上
- 画面収録の権限（初回起動時に許可が必要）

## ダウンロード

[最新版をダウンロード](https://github.com/piggest/Mas/releases/latest)

1. `Mas-x.x.x.dmg`をダウンロード
2. DMGを開いて`Mas.app`を`Applications`フォルダにドラッグ&ドロップ
3. 初回起動時に「開発元が未確認」の警告が出た場合は、システム設定 → プライバシーとセキュリティ → 「このまま開く」をクリック
4. 画面収録の権限を許可

## ソースからビルド

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
| キャプチャ枠表示 | `⌘⇧6` | 前回の範囲でキャプチャ枠を表示 |
| 全画面 | `⌘⇧3` | メインディスプレイ全体をキャプチャ |
| 範囲選択 | `⌘⇧4` | マウスドラッグで選択した範囲をキャプチャ |
| ウィンドウ | `⌘⇧5` | 特定のウィンドウをキャプチャ |

### メニューバーアイコン

- **シングルクリック**: メニューを表示
- **ダブルクリック**: 範囲選択キャプチャを開始

### メニュー機能

- **キャプチャモード選択**: 全画面、範囲選択、ウィンドウから選択
- **開いているウィンドウ一覧**: キャプチャ中のウィンドウを表示、クリックでフォーカス
- **すべて閉じる**: 開いているキャプチャウィンドウを一括で閉じる

### 範囲選択モード

1. `⌘⇧4`を押すと画面全体にオーバーレイが表示されます
2. マウスをドラッグして範囲を選択
3. マウスを離すとキャプチャが実行されます
4. `ESC`キーでキャンセル

### 編集機能

キャプチャ後、編集ウィンドウが表示されます。

1. **編集モードの開始**: 左下の鉛筆アイコンをクリック
2. **フローティングツールバー**: ウィンドウ下部にツールバーが表示されます

#### 利用可能なツール

| ツール | 説明 |
|--------|------|
| 選択 | アノテーションの選択・移動・リサイズ |
| ペン | フリーハンドで線を描画 |
| マーカー | 半透明のハイライト線を描画 |
| 矢印 | 矢印を描画 |
| 四角 | 矩形を描画 |
| 丸 | 円・楕円を描画 |
| テキスト | テキストを挿入 |
| ぼかし | モザイク効果を適用 |

#### 編集オプション

- **色の選択**: 10色のプリセットから選択（赤、橙、黄、緑、青、紫、ピンク、黒、白、グレー）
- **サイズ調整**: スライダーで線幅を1〜10の範囲で調整（ドラッグ中もリアルタイム反映）
- **縁取り**: テキストや図形に白い縁取りを追加
- **削除**: 選択中のアノテーションを削除
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
| キャプチャ枠表示 | `⌘⇧6` |
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
│       ├── FreehandAnnotation.swift
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
│   ├── FloatingToolbarWindow.swift # フローティングツールバー
│   ├── MenuBarView.swift         # メニューバーUI
│   ├── RegionSelectionOverlay.swift # 範囲選択オーバーレイ
│   ├── ResizableWindow.swift     # リサイズ可能ウィンドウ
│   ├── SettingsWindow.swift      # 設定画面
│   ├── ToolboxWindow.swift       # 編集ツールボックス（レガシー）
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
