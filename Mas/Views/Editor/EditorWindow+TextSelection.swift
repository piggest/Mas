import AppKit
import SwiftUI

// MARK: - テキスト選択モード（OCR ベース）
//
// このファイルは EditorWindow のテキスト選択モード関連ロジックを extension で集約する。
// Vision フレームワークで認識した文字列を矩形ハイライト・コピー対象として扱う。
//
// - textSelectionOverlay : 認識ブロックのヒント表示・選択ハイライト・コピーボタン UI
// - findCharIndex        : マウス座標から最も近い文字インデックスを探す
// - mergeSelectionRects  : 連続選択範囲の矩形を「同じ行ならマージ」する
// - startTextRecognition : OCR を非同期で起動し、結果を flatChars に展開する
// - buildFlatChars       : recognizedTexts を読み順にソート → 文字単位のフラット配列に変換
// - copySelectedText     : 選択範囲の文字をクリップボードへコピー（行間に改行を挿入）

extension EditorWindow {

    /// テキスト選択モードのオーバーレイ View。
    /// 認識ブロックの薄いヒント、文字単位の選択ハイライト、ローディング表示、
    /// コピーボタンを ZStack で重ねる。ドラッグジェスチャで選択範囲を更新する。
    @ViewBuilder
    var textSelectionOverlay: some View {
        let canvasHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height
        GeometryReader { geometry in
            ZStack {
                // テキストブロックの薄いヒント表示
                ForEach(Array(recognizedTexts.enumerated()), id: \.offset) { _, block in
                    let y = canvasHeight - block.rect.origin.y - block.rect.height
                    Rectangle()
                        .fill(Color.blue.opacity(0.04))
                        .border(Color.blue.opacity(0.12), width: 0.5)
                        .frame(width: block.rect.width, height: block.rect.height)
                        .position(x: block.rect.midX, y: y + block.rect.height / 2)
                        .allowsHitTesting(false)
                }

                // 文字単位の選択ハイライト
                if let start = charSelStart, let end = charSelEnd, !flatChars.isEmpty {
                    let lo = min(start, end)
                    let hi = max(start, end)
                    let clampedLo = max(0, lo)
                    let clampedHi = min(flatChars.count - 1, hi)
                    // 隣接する同じ行の文字をマージして描画
                    let mergedRects = mergeSelectionRects(from: clampedLo, to: clampedHi)
                    ForEach(Array(mergedRects.enumerated()), id: \.offset) { _, rect in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                }

                // ローディング表示
                if isRecognizingText {
                    VStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("テキスト認識中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }

                // 選択中テキストのコピーボタン
                if charSelStart != nil && charSelEnd != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { copySelectedText() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("コピー")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        charSelStart = findCharIndex(at: value.startLocation)
                        charSelEnd = findCharIndex(at: value.location)
                    }
                    .onEnded { value in
                        let distance = hypot(value.location.x - value.startLocation.x,
                                            value.location.y - value.startLocation.y)
                        if distance < 3 {
                            // クリック: 選択解除
                            charSelStart = nil
                            charSelEnd = nil
                        }
                    }
            )
        }
    }

    /// クリック/ドラッグ位置から最も近い文字のインデックスを探す。
    /// 1. 完全にヒットする文字を最優先
    /// 2. 同じ行（Y 距離が文字高の 60% 以内）で最も X が近い文字
    /// 3. それでもなければ閾値 20pt 以内で最も近い文字
    func findCharIndex(at point: CGPoint) -> Int? {
        // まず完全にヒットする文字を探す
        for (i, char) in flatChars.enumerated() {
            if char.rect.contains(point) {
                return i
            }
        }
        // Y座標が同じ行の文字を優先的に探す（行の高さの半分以内）
        var bestIndex: Int?
        var bestDist: CGFloat = .infinity
        for (i, char) in flatChars.enumerated() {
            let yDist = abs(point.y - char.rect.midY)
            // 行の高さの半分以内にある文字のみ対象
            if yDist <= char.rect.height * 0.6 {
                let xDist = abs(point.x - char.rect.midX)
                if xDist < bestDist {
                    bestDist = xDist
                    bestIndex = i
                }
            }
        }
        if bestIndex != nil { return bestIndex }
        // 同じ行がなければ、近い文字を探す（閾値を縮小）
        bestDist = .infinity
        for (i, char) in flatChars.enumerated() {
            let center = CGPoint(x: char.rect.midX, y: char.rect.midY)
            let dist = hypot(point.x - center.x, point.y - center.y)
            if dist < bestDist && dist < 20 {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// 連続する選択インデックスを矩形配列にまとめる。
    /// 同じ行（Y 中心の差が文字高の 50% 未満）の文字は水平方向に union してマージ。
    func mergeSelectionRects(from lo: Int, to hi: Int) -> [CGRect] {
        guard lo <= hi, lo >= 0, hi < flatChars.count else { return [] }
        if lo == hi {
            return [flatChars[lo].rect]
        }
        var result: [CGRect] = []
        var current = flatChars[lo].rect
        for i in (lo + 1)...hi {
            let charRect = flatChars[i].rect
            // 同じ行（Y座標が近い）なら水平方向にマージ
            if abs(charRect.midY - current.midY) < current.height * 0.5 {
                current = current.union(charRect)
            } else {
                result.append(current)
                current = charRect
            }
        }
        result.append(current)
        return result
    }

    /// OCR を非同期実行し、認識結果を `recognizedTexts` と `flatChars` に格納する。
    /// 二重起動を `isRecognizingText` フラグで防止する。
    func startTextRecognition() {
        guard !isRecognizingText else { return }
        isRecognizingText = true
        recognizedTexts = []
        flatChars = []
        charSelStart = nil
        charSelEnd = nil

        let image = screenshot.originalImage
        let canvasSize = CGSize(
            width: screenshot.captureRegion?.width ?? image.size.width,
            height: screenshot.captureRegion?.height ?? image.size.height
        )

        Task {
            let blocks = await textRecognitionService.recognizeText(in: image, imageSize: canvasSize)
            await MainActor.run {
                recognizedTexts = blocks
                buildFlatChars()
                isRecognizingText = false
            }
        }
    }

    /// 認識ブロックを読み順（上→下→左→右）にソートし、文字単位のフラット配列に展開。
    /// SwiftUI 表示用に座標系を「左下原点（NSView）」→「左上原点（SwiftUI）」へ変換する。
    func buildFlatChars() {
        let canvasHeight = screenshot.captureRegion?.height ?? screenshot.originalImage.size.height

        // ブロックを読み順にソート（上→下、同じ行なら左→右）
        let sortedBlocks = recognizedTexts.sorted { a, b in
            let aTop = canvasHeight - a.rect.maxY
            let bTop = canvasHeight - b.rect.maxY
            let lineThreshold = min(a.rect.height, b.rect.height) * 0.5
            if abs(aTop - bTop) > lineThreshold {
                return aTop < bTop
            }
            return a.rect.minX < b.rect.minX
        }

        var chars: [FlatTextChar] = []
        for block in sortedBlocks {
            let text = block.text
            for (i, charRect) in block.charRects.enumerated() {
                let y = canvasHeight - charRect.origin.y - charRect.height
                let swiftUIRect = CGRect(x: charRect.origin.x, y: y, width: charRect.width, height: charRect.height)
                let charIndex = text.index(text.startIndex, offsetBy: i)
                chars.append(FlatTextChar(
                    character: text[charIndex],
                    rect: swiftUIRect,
                    isBlockEnd: i == block.charRects.count - 1
                ))
            }
        }
        flatChars = chars
    }

    /// 選択中の文字をクリップボードへコピー。ブロック末尾（行末）には改行を挿入する。
    /// コピー後 1.5 秒間 `copiedToClipboard` を true にしてフィードバック UI を出す。
    func copySelectedText() {
        guard let start = charSelStart, let end = charSelEnd else { return }
        let lo = min(start, end)
        let hi = max(start, end)
        guard lo >= 0, hi < flatChars.count else { return }
        var result = ""
        for i in lo...hi {
            result.append(flatChars[i].character)
            if flatChars[i].isBlockEnd && i < hi {
                result.append("\n")
            }
        }
        guard !result.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedToClipboard = false
        }
    }
}
