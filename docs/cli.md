---
title: CLI リファレンス
layout: default
permalink: /cli/
---

# Mas CLI リファレンス

`mas-cli` はMasの全機能にコマンドラインからアクセスできるツールです。

## インストール

```bash
# ビルド
bash CLI/build.sh

# /usr/local/bin にインストール
bash CLI/install.sh
```

---

## キャプチャ

### 基本キャプチャ

```bash
# 全画面キャプチャ
mas-cli capture fullscreen

# 範囲選択キャプチャ
mas-cli capture region

# キャプチャ枠を表示
mas-cli capture frame

# GIF録画を開始
mas-cli capture gif

# 遅延付きキャプチャ（右クリックメニュー等の撮影に）
mas-cli capture fullscreen --delay 5
mas-cli capture region --delay 3
```

### UIキャプチャ

Masアプリの各UI要素を表示してからキャプチャします。

```bash
# メニューポップオーバー
mas-cli capture menu --output menu.png

# ライブラリウィンドウ
mas-cli capture library --output library.png

# 設定ウィンドウ
mas-cli capture settings --output settings.png

# エディターウィンドウ
mas-cli capture editor --output editor.png
```

### ウィンドウキャプチャ

```bash
# Masウィンドウ一覧
mas-cli capture window

# 指定ウィンドウIDをキャプチャ
mas-cli capture window <id> --output window.png
```

### 汎用遅延キャプチャ

```bash
# デフォルト5秒後に全画面キャプチャ
mas-cli capture delayed --output screenshot.png

# 3秒後にキャプチャ
mas-cli capture delayed --delay 3 --output screenshot.png
```

### デモ画像生成

全画面をキャプチャし、全アノテーション種（矢印・四角・丸・テキスト・ハイライト・モザイク）を自動配置したデモ画像を生成します。

```bash
# デモ画像を生成
mas-cli capture demo --output docs/images/annotations-demo.png
```

### ドキュメント用一括撮影

メニュー・設定・ライブラリのスクリーンショットを一括で撮影します。

```bash
# docs/images/ に一括撮影（デフォルト）
mas-cli capture all-docs

# 出力先ディレクトリを指定
mas-cli capture all-docs --output-dir docs/images
```

撮影されるファイル:

| ファイル | 内容 |
|---------|------|
| `menu.png` | メニューバーポップオーバー |
| `settings.png` | 設定画面 |
| `library.png` | ライブラリウィンドウ |

---

## アノテーション

画像にアノテーションをプログラマティックに追加します。

### 矢印

```bash
mas-cli annotate image.png arrow --from 100,200 --to 300,400 --color red --width 3 --output out.png
```

### 四角

```bash
# 枠線のみ
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --width 2 --output out.png

# 塗りつぶし
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --filled --output out.png
```

### 丸（楕円）

```bash
mas-cli annotate image.png ellipse --rect 100,100,200,200 --color green --width 3 --output out.png
```

### テキスト

```bash
mas-cli annotate image.png text --pos 100,50 --text "ここに注目" --size 24 --color red --output out.png
```

### ハイライト

```bash
mas-cli annotate image.png highlight --rect 50,100,300,30 --color yellow --output out.png
```

### モザイク

```bash
mas-cli annotate image.png mosaic --rect 100,100,200,50 --pixel-size 15 --output out.png
```

### 共通オプション

| オプション | 説明 | デフォルト |
|-----------|------|----------|
| `--output path` | 出力先（省略時は元画像を上書き） | 元画像 |
| `--color name` | 色名または `#RRGGBB` | `red` |
| `--width N` | 線の太さ | `3` |
| `--no-stroke` | 縁取りなし | 縁取りあり |
| `--filled` | 塗りつぶし（rect/ellipse） | 枠線のみ |

### 使用可能な色名

`red`, `blue`, `green`, `yellow`, `orange`, `white`, `black`, `purple`, `#RRGGBB`

### 複数アノテーションの適用

パイプラインで連続適用できます：

```bash
mas-cli annotate image.png rect --rect 50,50,200,100 --color red --output /tmp/step1.png
mas-cli annotate /tmp/step1.png arrow --from 250,100 --to 150,75 --color red --output /tmp/step2.png
mas-cli annotate /tmp/step2.png text --pos 260,90 --text "注目" --size 18 --color red --output final.png
```

---

## テキスト認識（OCR）

```bash
# テキスト抽出
mas-cli ocr screenshot.png

# JSON形式で座標情報付き出力
mas-cli ocr screenshot.png --json
```

---

## 履歴管理

```bash
# 一覧
mas-cli history list

# お気に入りのみ
mas-cli history list --favorites

# JSON出力
mas-cli history list --json

# 削除（IDの先頭数文字で指定可能）
mas-cli history delete a1b2c3d4
```

---

## 設定

```bash
# 一覧
mas-cli settings list

# 取得
mas-cli settings get playSound

# 変更
mas-cli settings set playSound false
mas-cli settings set defaultFormat JPEG
mas-cli settings set jpegQuality 0.8
mas-cli settings set pinBehavior latestOnly
```

### 設定キー一覧

| キー | 説明 | 型 | 値の例 |
|-----|------|------|-------|
| `developerMode` | 開発者モード | Bool | `true` / `false` |
| `defaultFormat` | 保存形式 | String | `PNG` / `JPEG` |
| `jpegQuality` | JPEG品質 | Double | `0.1` 〜 `1.0` |
| `showCursor` | マウスカーソルを含める | Bool | `true` / `false` |
| `playSound` | キャプチャ時にサウンド再生 | Bool | `true` / `false` |
| `autoSaveEnabled` | ファイルに保存 | Bool | `true` / `false` |
| `autoSaveFolder` | 保存先フォルダ | String | パス |
| `autoCopyToClipboard` | クリップボードにコピー | Bool | `true` / `false` |
| `closeOnDragSuccess` | ドラッグ成功時に閉じる | Bool | `true` / `false` |
| `pinBehavior` | ピン動作 | String | `alwaysOn` / `latestOnly` / `off` |

---

## その他

```bash
# 画像をエディタで開く
mas-cli open ~/Desktop/screenshot.png

# バージョン表示
mas-cli version

# アプリの起動状態を確認
mas-cli status
```

---

## 使用例

### ドキュメント用スクリーンショットの自動化

```bash
# 1. 一括撮影でUI系スクリーンショットを取得
mas-cli capture all-docs --output-dir docs/images

# 2. デモ画像を生成
mas-cli capture demo --output docs/images/annotations-demo.png

# 3. エディターウィンドウを撮影（事前にエディターを開いておく）
mas-cli capture editor --output docs/images/editor.png
```

### アノテーション付き画像の自動生成

```bash
# スクリーンショットを撮って注釈を追加
mas-cli capture delayed --delay 3 --output /tmp/raw.png
mas-cli annotate /tmp/raw.png rect --rect 50,50,200,100 --color red --output /tmp/step1.png
mas-cli annotate /tmp/step1.png arrow --from 250,100 --to 150,75 --color red --output /tmp/step2.png
mas-cli annotate /tmp/step2.png text --pos 260,90 --text "注目" --size 18 --color red --output final.png
```

### CI/CDでのスクリーンショット取得

```bash
# 設定変更 → キャプチャ → 設定復元
mas-cli settings set playSound false
mas-cli capture fullscreen --delay 2
mas-cli settings set playSound true
```

---

## 備考

- キャプチャ系コマンド（`fullscreen`, `region`, `frame`, `gif`）はMas.appへの通知として送信されます。アプリが未起動の場合は自動的に起動します。
- OCR、履歴、設定、アノテーションコマンドはスタンドアロンで動作し、アプリの起動は不要です。
- `capture menu` / `capture library` / `capture settings` は対象UIを表示してからウィンドウをキャプチャします。
- `capture demo` はスタンドアロンで全画面キャプチャ後にアノテーションを適用します。
- `capture all-docs` はMas.appを自動起動し、各UIを順番に表示・キャプチャします。
