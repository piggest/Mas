---
title: アノテーション詳細ガイド
layout: default
---

# Mas アノテーション詳細ガイド

Masのエディターウィンドウでは、フローティングツールバーから各種アノテーションを画像に追加できます。
すべてのアノテーションは [CLI](cli.md) からもプログラマティックに追加可能です。

---

## 座標系

アノテーションの座標は画像のピクセル座標で指定します。

- **原点**: 左上 (0, 0)
- **X軸**: 右方向が正
- **Y軸**: 下方向が正
- **単位**: ピクセル

GUI操作時はキャンバス上のマウス位置から自動的に画像座標に変換されます。

---

## アノテーション種別

### 矢印 (arrow)

テーパー形状の矢印を描画します。尻尾が細く、先端に向かって太くなります。

**プロパティ:**
- 開始点 (startPoint) / 終了点 (endPoint)
- 色 (color)
- 線の太さ (lineWidth) — 矢印全体のサイズに影響
- 縁取り (strokeEnabled) — 黒い外縁 + 白い境界線

**GUIでの使い方:**
1. ツールバーから「矢印」を選択
2. 画像上で始点からドラッグ
3. ドロップした位置が矢印の先端

**CLI:**
```bash
mas-cli annotate image.png arrow --from 100,200 --to 300,150 --color red --width 4
```

---

### 四角 (rect)

四角形を描画します。枠線のみまたは半透明の塗りつぶしが選べます。

**プロパティ:**
- 矩形領域 (rect: x, y, width, height)
- 色 (color)
- 線の太さ (lineWidth)
- 塗りつぶし (isFilled) — 有効時は alpha=0.3 で塗りつぶし
- 縁取り (strokeEnabled) — 黒い外縁 + 白い境界線

**GUIでの使い方:**
1. ツールバーから「四角」を選択
2. 画像上で左上からドラッグして範囲を決定

**CLI:**
```bash
# 枠線のみ
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --width 2

# 塗りつぶし
mas-cli annotate image.png rect --rect 50,50,200,150 --color blue --filled
```

---

### 丸 (ellipse)

楕円を描画します。四角と同じオプションが使えます。

**プロパティ:**
- 矩形領域 (rect) — この矩形に内接する楕円
- 色 (color)
- 線の太さ (lineWidth)
- 塗りつぶし (isFilled)
- 縁取り (strokeEnabled)

**GUIでの使い方:**
1. ツールバーから「丸」を選択
2. 画像上でドラッグして楕円の外接矩形を決定

**CLI:**
```bash
mas-cli annotate image.png ellipse --rect 100,100,200,200 --color green --width 3
```

---

### テキスト (text)

画像上にテキストを追加します。3段階の描画で視認性を確保します。

**描画方式（縁取り有効時）:**
1. 黒い外縁アウトライン（最も太い）
2. 白いストローク（中間）
3. 元の色で塗りつぶし

**プロパティ:**
- 位置 (position) — テキストのベースライン位置
- テキスト内容 (text)
- フォントサイズ (fontSize)
- 色 (color)
- 縁取り (strokeEnabled)

**GUIでの使い方:**
1. ツールバーから「文字」を選択
2. 画像上の配置したい位置をクリック
3. テキストを入力

**CLI:**
```bash
mas-cli annotate image.png text --pos 100,50 --text "ここに注目" --size 24 --color red
```

---

### マーカー / ハイライト (highlight)

半透明の矩形を描画します。重要な箇所のマークアップに最適です。

**プロパティ:**
- 矩形領域 (rect)
- 色 (color) — alpha=0.4 で描画

**GUIでの使い方:**
1. ツールバーから「マーカー」を選択
2. 画像上でドラッグして範囲を決定

**CLI:**
```bash
mas-cli annotate image.png highlight --rect 50,100,300,30 --color yellow
```

---

### ペン (freehand)

マウスの軌跡に沿って自由に線を描画します。

**プロパティ:**
- 点列 (points) — マウスの軌跡
- 色 (color)
- 線の太さ (lineWidth)
- マーカーモード (isHighlighter) — 有効時は太さ3倍、alpha=0.4
- 縁取り (strokeEnabled) — マーカー以外で有効

**GUIでの使い方:**
1. ツールバーから「ペン」（または「マーカー」）を選択
2. 画像上でドラッグして描画

> CLIからはフリーハンドの点列指定が複雑なため、GUI利用を推奨します。

---

### ぼかし / モザイク (mosaic)

指定領域にピクセル化（モザイク）効果を適用します。個人情報や機密情報のマスキングに使えます。

**プロパティ:**
- 矩形領域 (rect)
- ピクセルサイズ (pixelSize) — 値が大きいほど荒いモザイク

**実装:** Core Image の `CIPixellate` フィルタを使用。

**GUIでの使い方:**
1. ツールバーから「ぼかし」を選択
2. 画像上でドラッグしてモザイク領域を決定

**CLI:**
```bash
mas-cli annotate image.png mosaic --rect 100,100,200,50 --pixel-size 15
```

---

### トリミング (trim)

画像の一部を切り出します。

**GUIでの使い方:**
1. ツールバーから「トリミング」を選択
2. 画像上でドラッグして切り出し範囲を決定
3. 確定ボタンで切り出しを適用

> トリミングはCLIからは利用できません。

---

## 共通操作

### 色の選択

ツールバーの色パレットから6色を選択できます：
赤、青、緑、黄、オレンジ、白

### 太さの調整

ツールバーのスライダーで線の太さを調整します（1〜30pt）。
太さはペン、矢印、四角、丸、ぼかしの各ツールに影響します。

### 縁取り

ツールバーのトグルで縁取りの有効/無効を切り替えます。
縁取りは3段階の描画（黒い外縁 → 白い境界線 → 元の色）で、どんな背景でも視認性を確保します。

### 移動

1. ツールバーから「移動」を選択
2. アノテーションをクリックして選択
3. ドラッグで移動

### 削除

- アノテーション選択中に `Delete` キー
- またはツールバーの削除ボタン

### Undo / Redo

ツールバーのUndoボタンで最大50段階まで元に戻せます。

---

## データ形式

アノテーションは JSON 形式で保存されます。

**保存先:** `~/Library/Application Support/Mas/annotations/{UUID}.json`

各アノテーションは以下のフィールドを持つ `CodableAnnotation` 構造体です：

```json
{
  "kind": "arrow",
  "colorR": 1.0, "colorG": 0.23, "colorB": 0.19, "colorA": 1.0,
  "lineWidth": 3.0,
  "strokeEnabled": true,
  "startX": 100.0, "startY": 200.0,
  "endX": 300.0, "endY": 150.0
}
```

### kind 別フィールド

| kind | 必須フィールド |
|------|--------------|
| `arrow` | `startX`, `startY`, `endX`, `endY` |
| `rect` | `rectX`, `rectY`, `rectW`, `rectH`, `isFilled` |
| `ellipse` | `rectX`, `rectY`, `rectW`, `rectH`, `isFilled` |
| `text` | `posX`, `posY`, `text`, `fontSize` |
| `highlight` | `rectX`, `rectY`, `rectW`, `rectH` |
| `freehand` | `points` (配列の配列 `[[x,y], ...]`), `isHighlighter` |
| `mosaic` | `rectX`, `rectY`, `rectW`, `rectH`, `pixelSize` |

### 共通フィールド

| フィールド | 型 | 説明 |
|-----------|------|------|
| `kind` | String | アノテーション種別 |
| `colorR/G/B/A` | Double | RGBA カラー成分 (0.0〜1.0) |
| `lineWidth` | Double? | 線の太さ |
| `strokeEnabled` | Bool? | 縁取りの有効/無効 |
