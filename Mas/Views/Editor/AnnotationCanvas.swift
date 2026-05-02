import AppKit
import SwiftUI

// MARK: - AnnotationCanvas 関連
//
// このファイルは編集モードでのアノテーション描画・編集ロジックを担う。
// SwiftUI 側からは AnnotationCanvasView 経由で利用される。
//
// - AnnotationCanvasView: NSViewRepresentable。SwiftUI と NSView を橋渡しする
// - AnnotationCanvasDelegate: アノテーション追加・選択時のコールバック契約
// - AnnotationCanvas: 実際の描画・マウスイベント・ヒットテストを行う NSView 本体

// 注釈描画キャンバス
struct AnnotationCanvasView: NSViewRepresentable {
    @Binding var annotations: [any Annotation]
    @Binding var currentAnnotation: (any Annotation)?
    let selectedTool: EditTool
    let selectedColor: NSColor
    let lineWidth: CGFloat
    let strokeEnabled: Bool
    let sourceImage: NSImage
    let isEditing: Bool
    let showImage: Bool
    let toolboxState: ToolboxState
    let onTextTap: (CGPoint) -> Void
    let onArrowTextDragFinished: ((CGPoint, CGPoint) -> Void)?
    let onAnnotationChanged: () -> Void
    let onTextEdit: ((Int, TextAnnotation) -> Void)?
    let onDoubleClickEmpty: (() -> Void)?
    let onSelectionChanged: ((Int?) -> Void)?
    let onToolChanged: ((EditTool) -> Void)?
    var onTrimRequested: ((CGRect) -> Void)?
    var onCopyTrimRegion: ((CGRect) -> Void)?
    var onCopyText: (() -> Void)?
    var imageDisplaySize: CGSize = .zero

    func makeNSView(context: Context) -> AnnotationCanvas {
        let canvas = AnnotationCanvas()
        canvas.delegate = context.coordinator
        canvas.sourceImage = sourceImage
        canvas.imageDisplaySize = imageDisplaySize
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateNSView(_ nsView: AnnotationCanvas, context: Context) {
        // ツール変更時にトリミング選択範囲をクリア
        if nsView.selectedTool != selectedTool {
            nsView.trimRect = nil
        }
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.selectedTool = selectedTool
        nsView.selectedColor = selectedColor
        nsView.lineWidth = lineWidth
        nsView.strokeEnabled = strokeEnabled
        nsView.sourceImage = sourceImage
        nsView.imageDisplaySize = imageDisplaySize
        nsView.isEditing = isEditing
        nsView.showImage = showImage
        // 編集モード終了時に選択をクリア
        if !isEditing {
            nsView.clearSelection()
            // 状態変更を次のRunLoopサイクルに遅延（クラッシュ防止）
            if toolboxState.selectedAnnotationIndex != nil {
                let state = toolboxState
                DispatchQueue.main.async {
                    state.selectedAnnotationIndex = nil
                }
            }
        } else {
            // ToolboxStateの選択状態をCanvasに同期
            nsView.setSelectedIndex(toolboxState.selectedAnnotationIndex)
        }
        // ウィンドウフレームを更新
        nsView.updateWindowFrame()
        // リアルタイムキャプチャモードのタイマー制御
        nsView.updateRefreshTimer(hasMosaicAnnotations: annotations.contains { $0 is MosaicAnnotation })
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AnnotationCanvasDelegate {
        var parent: AnnotationCanvasView
        weak var canvas: AnnotationCanvas?

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func annotationAdded(_ annotation: any Annotation) {
            // モザイクは常に後ろ（配列の先頭）に追加
            let newIndex: Int
            if annotation is MosaicAnnotation {
                parent.annotations.insert(annotation, at: 0)
                newIndex = 0
            } else {
                parent.annotations.append(annotation)
                newIndex = parent.annotations.count - 1
            }
            // 直接canvasの配列も更新（同期問題を回避）
            canvas?.annotations = parent.annotations
            canvas?.needsDisplay = true

            parent.currentAnnotation = nil
            parent.onAnnotationChanged()

            // ペン・マーカー以外の場合のみ選択モードに切り替え
            if !(annotation is FreehandAnnotation) {
                parent.onToolChanged?(.move)
                parent.toolboxState.selectedAnnotationIndex = newIndex
                canvas?.setSelectedIndex(newIndex)
                canvas?.needsDisplay = true
            }
        }

        func currentAnnotationUpdated(_ annotation: (any Annotation)?) {
            parent.currentAnnotation = annotation
        }

        func textTapped(at position: CGPoint) {
            parent.onTextTap(position)
        }

        func arrowTextDragFinished(startPoint: CGPoint, endPoint: CGPoint) {
            parent.currentAnnotation = nil
            parent.onArrowTextDragFinished?(startPoint, endPoint)
        }

        func annotationMoved() {
            // canvasの配列を親に反映
            if let canvasAnnotations = canvas?.annotations {
                parent.annotations = canvasAnnotations
            }
            parent.onAnnotationChanged()
        }

        func selectionChanged(_ index: Int?) {
            parent.toolboxState.selectedAnnotationIndex = index
            // 選択時にアノテーションの属性をツールボックスに読み込み
            parent.onSelectionChanged?(index)
        }

        func deleteSelectedAnnotation() {
            guard let index = parent.toolboxState.selectedAnnotationIndex,
                  index < parent.annotations.count else { return }
            parent.annotations.remove(at: index)
            canvas?.annotations = parent.annotations

            // 削除後に次のアノテーションを自動選択
            let newIndex: Int?
            if parent.annotations.isEmpty {
                newIndex = nil
            } else if index < parent.annotations.count {
                // 同じ位置に次のアノテーションがあればそれを選択
                newIndex = index
            } else {
                // 最後の要素だった場合は一つ前を選択
                newIndex = parent.annotations.count - 1
            }

            canvas?.setSelectedIndex(newIndex)
            parent.toolboxState.selectedAnnotationIndex = newIndex
            canvas?.needsDisplay = true
            parent.onAnnotationChanged()
        }

        func editTextAnnotation(at index: Int, annotation: TextAnnotation) {
            parent.onTextEdit?(index, annotation)
        }

        func doubleClickedOnEmpty() {
            parent.onDoubleClickEmpty?()
        }

        func trimRequested(rect: CGRect) {
            parent.onTrimRequested?(rect)
        }

        func copyTrimRegionRequested(rect: CGRect) {
            parent.onCopyTrimRegion?(rect)
        }

        func copyTextRequested() {
            parent.onCopyText?()
        }
    }
}

protocol AnnotationCanvasDelegate: AnyObject {
    func annotationAdded(_ annotation: any Annotation)
    func currentAnnotationUpdated(_ annotation: (any Annotation)?)
    func textTapped(at position: CGPoint)
    func arrowTextDragFinished(startPoint: CGPoint, endPoint: CGPoint)
    func annotationMoved()
    func selectionChanged(_ index: Int?)
    func deleteSelectedAnnotation()
    func editTextAnnotation(at index: Int, annotation: TextAnnotation)
    func doubleClickedOnEmpty()
    func trimRequested(rect: CGRect)
    func copyTrimRegionRequested(rect: CGRect)
    func copyTextRequested()
}

// ResizeHandle は Mas/Logic/AnnotationGeometry.swift に移動済み

class AnnotationCanvas: NSView {
    weak var delegate: AnnotationCanvasDelegate?
    var annotations: [any Annotation] = []
    var currentAnnotation: (any Annotation)?
    var selectedTool: EditTool = .arrow
    var selectedColor: NSColor = .red
    var lineWidth: CGFloat = 3
    var strokeEnabled: Bool = true
    var sourceImage: NSImage?
    var imageDisplaySize: CGSize = .zero  // 画像の表示サイズ（モザイクのスケール計算用）
    var isEditing: Bool = false
    var showImage: Bool = true
    private var dragStart: CGPoint?
    private var selectedAnnotationIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMoveAnnotation: Bool = false
    private var windowFrame: CGRect = .zero
    private var refreshTimer: Timer?
    private var activeResizeHandle: ResizeHandle = .none
    private var isResizing: Bool = false
    var trimRect: CGRect?
    private var trimDragStart: CGPoint?

    /// キャンバス内の画像領域オフセット（全方向パディング対応）
    private var canvasPadding: CGPoint {
        guard imageDisplaySize.width > 0, imageDisplaySize.height > 0 else { return .zero }
        let px = max(0, (bounds.width - imageDisplaySize.width) / 2)
        let py = max(0, (bounds.height - imageDisplaySize.height) / 2)
        return CGPoint(x: px, y: py)
    }

    /// マウスイベント座標を画像座標系に変換
    private func imagePoint(from event: NSEvent) -> CGPoint {
        let raw = convert(event.locationInWindow, from: nil)
        let pad = canvasPadding
        return CGPoint(x: raw.x - pad.x, y: raw.y - pad.y)
    }

    override var acceptsFirstResponder: Bool { true }

    override var mouseDownCanMoveWindow: Bool { !isEditing }

    func clearSelection() {
        selectedAnnotationIndex = nil
    }

    func setSelectedIndex(_ index: Int?) {
        selectedAnnotationIndex = index
    }

    func updateWindowFrame() {
        if let windowFrame = window?.frame {
            self.windowFrame = windowFrame
        }
    }

    private var needsRefreshTimer: Bool = false

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        // 約30fpsでリアルタイム更新
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.needsRefreshTimer else { return }
            // モザイクのキャッシュをクリアして再描画
            for annotation in self.annotations {
                if let mosaic = annotation as? MosaicAnnotation {
                    mosaic.clearCache()
                }
            }
            self.needsDisplay = true
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshTimer(hasMosaicAnnotations: Bool) {
        needsRefreshTimer = !showImage && hasMosaicAnnotations
        if needsRefreshTimer {
            startRefreshTimer()
        }
        // タイマーは停止しない（再開コストが高いため）
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 編集モードでない場合、またはテキスト選択モードの場合はヒットテストを無効にして
        // イベントをSwiftUIオーバーレイに通過させる
        if !isEditing || selectedTool == .textSelection {
            return nil
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // ウィンドウフレームを更新
        updateWindowFrame()
        let winNum = window?.windowNumber ?? 0
        // モザイクのスケール計算には画像表示サイズを使用
        let imgSize = imageDisplaySize.width > 0 ? imageDisplaySize : bounds.size
        let imgBounds = NSRect(origin: .zero, size: imgSize)

        // キャンバスが画像より大きい場合、描画を画像領域にオフセット（全方向パディング対応）
        let pad = canvasPadding
        let hasPadding = pad.x > 0 || pad.y > 0
        if hasPadding {
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.translateBy(x: pad.x, y: pad.y)
        }

        // 配列の順序通りに描画（インデックス0が最背面、最後が最前面）
        for (index, annotation) in annotations.enumerated() {
            // モザイクアノテーションの場合、リアルタイムキャプチャモードを設定
            if let mosaic = annotation as? MosaicAnnotation {
                mosaic.useRealTimeCapture = !showImage
                mosaic.windowFrame = windowFrame
                mosaic.windowNumber = winNum
                mosaic.canvasSize = imgSize
            }
            annotation.draw(in: imgBounds)
            // 編集モード中の移動モードのみバウンディングボックスを描画
            if isEditing && selectedTool == .move {
                let isSelected = index == selectedAnnotationIndex
                drawBoundingBox(for: annotation, isSelected: isSelected)
            }
        }

        // 現在描画中のアノテーション
        if let current = currentAnnotation {
            if let mosaic = current as? MosaicAnnotation {
                mosaic.useRealTimeCapture = !showImage
                mosaic.windowFrame = windowFrame
                mosaic.windowNumber = winNum
                mosaic.canvasSize = imgSize
            }
            current.draw(in: imgBounds)
        }

        // トリミング選択範囲の描画
        if selectedTool == .trim, let trimRect = trimRect {
            drawTrimOverlay(trimRect: trimRect)
        }

        if hasPadding {
            NSGraphicsContext.current?.cgContext.restoreGState()
        }
    }

    private func drawTrimOverlay(trimRect: CGRect) {
        // 選択範囲外を半透明黒でオーバーレイ
        let overlayPath = NSBezierPath(rect: bounds)
        overlayPath.appendRect(trimRect)
        overlayPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        overlayPath.fill()

        // 選択範囲に白枠
        let borderPath = NSBezierPath(rect: trimRect)
        borderPath.lineWidth = 1.5
        NSColor.white.setStroke()
        borderPath.stroke()

        // 選択範囲に青点線
        let dashPath = NSBezierPath(rect: trimRect)
        dashPath.lineWidth = 1.5
        let dashPattern: [CGFloat] = [6, 4]
        dashPath.setLineDash(dashPattern, count: 2, phase: 0)
        NSColor.systemBlue.setStroke()
        dashPath.stroke()

        // 右下にサイズ表示
        let width = Int(trimRect.width)
        let height = Int(trimRect.height)
        let sizeText = "\(width) x \(height)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let textSize = sizeText.size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: trimRect.maxX - textSize.width - 4,
            y: trimRect.minY + 4
        )
        sizeText.draw(at: textPoint, withAttributes: attributes)
    }

    private func drawBoundingBox(for annotation: any Annotation, isSelected: Bool) {
        let highlightPath = NSBezierPath()
        highlightPath.lineWidth = isSelected ? 2 : 1

        var boundingRect: CGRect = .zero

        if let line = annotation as? LineAnnotation {
            boundingRect = line.boundingRect()
            highlightPath.appendRect(boundingRect)
        } else if let arrow = annotation as? ArrowAnnotation {
            boundingRect = arrow.boundingRect()
            highlightPath.appendRect(boundingRect)
        } else if let rect = annotation as? RectAnnotation {
            boundingRect = rect.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let ellipse = annotation as? EllipseAnnotation {
            boundingRect = ellipse.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let text = annotation as? TextAnnotation {
            let size = text.textSize()
            let drawY = text.position.y - text.font.ascender
            boundingRect = CGRect(origin: CGPoint(x: text.position.x - 3, y: drawY - 3), size: CGSize(width: size.width + 6, height: size.height + 6))
            highlightPath.appendRect(boundingRect)
        } else if let mosaic = annotation as? MosaicAnnotation {
            boundingRect = mosaic.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        } else if let freehand = annotation as? FreehandAnnotation {
            boundingRect = freehand.boundingRect()
            highlightPath.appendRect(boundingRect)
        } else if let highlight = annotation as? HighlightAnnotation {
            boundingRect = highlight.rect.insetBy(dx: -3, dy: -3)
            highlightPath.appendRect(boundingRect)
        }

        let dashPattern: [CGFloat] = [4, 4]
        highlightPath.setLineDash(dashPattern, count: 2, phase: 0)

        if isSelected {
            NSColor.systemBlue.setStroke()
        } else {
            NSColor.gray.withAlphaComponent(0.6).setStroke()
        }
        highlightPath.stroke()

        // 選択中のアノテーションにリサイズハンドルを描画
        if isSelected {
            if let line = annotation as? LineAnnotation {
                // 直線は始点と終点にハンドル
                drawResizeHandle(at: line.startPoint)
                drawResizeHandle(at: line.endPoint)
            } else if let arrow = annotation as? ArrowAnnotation {
                // 矢印は始点と終点にハンドル
                drawResizeHandle(at: arrow.startPoint)
                drawResizeHandle(at: arrow.endPoint)
            } else if annotation is RectAnnotation || annotation is EllipseAnnotation || annotation is MosaicAnnotation {
                // 四角形系は四隅にハンドル
                drawResizeHandle(at: CGPoint(x: boundingRect.minX, y: boundingRect.minY))
                drawResizeHandle(at: CGPoint(x: boundingRect.maxX, y: boundingRect.minY))
                drawResizeHandle(at: CGPoint(x: boundingRect.minX, y: boundingRect.maxY))
                drawResizeHandle(at: CGPoint(x: boundingRect.maxX, y: boundingRect.maxY))
            }
        }
    }

    private func drawResizeHandle(at point: CGPoint) {
        let handleSize: CGFloat = 8
        let handleRect = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2, width: handleSize, height: handleSize)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(ovalIn: handleRect)
        path.lineWidth = 1.5
        path.stroke()
    }

    /// リサイズハンドルのヒットテスト
    private func hitTestResizeHandle(at point: CGPoint) -> ResizeHandle {
        guard let index = selectedAnnotationIndex, index < annotations.count else {
            return .none
        }

        let handleSize: CGFloat = 12  // ヒットエリアは少し大きめに
        let annotation = annotations[index]

        if let line = annotation as? LineAnnotation {
            // 直線は始点と終点をチェック
            if CGRect(x: line.startPoint.x - handleSize / 2, y: line.startPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .startPoint
            }
            if CGRect(x: line.endPoint.x - handleSize / 2, y: line.endPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .endPoint
            }
        } else if let arrow = annotation as? ArrowAnnotation {
            // 矢印は始点と終点をチェック
            if CGRect(x: arrow.startPoint.x - handleSize / 2, y: arrow.startPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .startPoint
            }
            if CGRect(x: arrow.endPoint.x - handleSize / 2, y: arrow.endPoint.y - handleSize / 2, width: handleSize, height: handleSize).contains(point) {
                return .endPoint
            }
        } else if let rect = annotation as? RectAnnotation {
            return hitTestCorners(rect: rect.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        } else if let ellipse = annotation as? EllipseAnnotation {
            return hitTestCorners(rect: ellipse.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        } else if let mosaic = annotation as? MosaicAnnotation {
            return hitTestCorners(rect: mosaic.rect.insetBy(dx: -3, dy: -3), point: point, handleSize: handleSize)
        }

        return .none
    }

    /// 四隅のハンドルをヒットテスト
    private func hitTestCorners(rect: CGRect, point: CGPoint, handleSize: CGFloat) -> ResizeHandle {
        let corners: [(CGPoint, ResizeHandle)] = [
            (CGPoint(x: rect.minX, y: rect.minY), .bottomLeft),
            (CGPoint(x: rect.maxX, y: rect.minY), .bottomRight),
            (CGPoint(x: rect.minX, y: rect.maxY), .topLeft),
            (CGPoint(x: rect.maxX, y: rect.maxY), .topRight)
        ]

        for (cornerPoint, handle) in corners {
            let hitRect = CGRect(x: cornerPoint.x - handleSize / 2, y: cornerPoint.y - handleSize / 2, width: handleSize, height: handleSize)
            if hitRect.contains(point) {
                return handle
            }
        }
        return .none
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        // テキスト選択モードはSwiftUIオーバーレイで処理
        if selectedTool == .textSelection { return }

        let point = imagePoint(from: event)
        dragStart = point
        lastDragPoint = point

        // ダブルクリック処理
        if event.clickCount == 2 {
            // 移動モードでテキストアノテーション上ならテキスト編集
            if selectedTool == .move {
                for (index, annotation) in annotations.enumerated().reversed() {
                    if let textAnnotation = annotation as? TextAnnotation,
                       textAnnotation.contains(point: point) {
                        delegate?.editTextAnnotation(at: index, annotation: textAnnotation)
                        return
                    }
                }
            }
            // 空白部分のダブルクリック - 画像を非表示
            let hitAnnotation = annotations.contains { $0.contains(point: point) }
            if !hitAnnotation {
                delegate?.doubleClickedOnEmpty()
                return
            }
        }

        // トリミングモードの場合
        if selectedTool == .trim {
            trimDragStart = point
            trimRect = nil
            needsDisplay = true
            return
        }

        // 移動モードの場合
        if selectedTool == .move {
            // まずリサイズハンドルのヒットテストを行う
            let handle = hitTestResizeHandle(at: point)
            if handle != .none {
                activeResizeHandle = handle
                isResizing = true
                return
            }

            // 前の選択状態を記録（インデックスが有効な場合のみ）
            let previousSelectedIndex = selectedAnnotationIndex
            let previousWasMosaic: Bool = {
                guard let index = previousSelectedIndex, index < annotations.count else { return false }
                return annotations[index] is MosaicAnnotation
            }()

            // クリックした位置にあるアノテーションを探す（配列のインデックス順）
            let clickedIndices = annotations.enumerated()
                .filter { $0.element.contains(point: point) }
                .map { $0.offset }

            if clickedIndices.isEmpty {
                // 何もない場所をクリック - 選択解除してウィンドウドラッグ開始
                // ぼかしが選択されていたら最背面に移動
                if previousWasMosaic, let prevIndex = previousSelectedIndex {
                    moveMosaicToBack(at: prevIndex)
                }
                selectedAnnotationIndex = nil
                delegate?.selectionChanged(nil)
                needsDisplay = true
                // ウィンドウドラッグを開始
                window?.performDrag(with: event)
                return
            } else if let currentIndex = previousSelectedIndex, clickedIndices.contains(currentIndex) {
                // 選択中のオブジェクトがクリックされた場合 - サイクル選択
                // 現在選択中の要素を後ろに移動（ただしぼかしより後ろには行かない）
                let movedAnnotation = annotations.remove(at: currentIndex)

                if movedAnnotation is MosaicAnnotation {
                    // ぼかしの場合は最背面（インデックス0）に移動
                    annotations.insert(movedAnnotation, at: 0)
                } else {
                    // ぼかし以外の場合、ぼかしの直後に移動
                    let mosaicCount = annotations.filter { $0 is MosaicAnnotation }.count
                    annotations.insert(movedAnnotation, at: mosaicCount)
                }

                // インデックスを再計算してクリック位置のオブジェクトを探す
                let newClickedIndices = annotations.enumerated()
                    .filter { $0.element.contains(point: point) }
                    .map { $0.offset }

                // 一番上のオブジェクトを選択
                if let topIndex = newClickedIndices.last {
                    selectedAnnotationIndex = topIndex
                    // ぼかしが選択された場合は最前面に移動
                    if annotations[topIndex] is MosaicAnnotation {
                        moveMosaicToFront(at: topIndex)
                    }
                } else {
                    selectedAnnotationIndex = nil
                }

                // 配列が変更されたのでcanvasを更新
                delegate?.annotationMoved()
            } else {
                // 新しいオブジェクトを選択
                // 前に選択していたぼかしは最背面に移動
                if previousWasMosaic, let prevIndex = previousSelectedIndex {
                    moveMosaicToBack(at: prevIndex)
                }

                // 一番上のオブジェクトを選択（インデックスが最大のもの）
                if let topIndex = clickedIndices.last {
                    selectedAnnotationIndex = topIndex
                    // ぼかしが選択された場合は最前面に移動
                    if annotations[topIndex] is MosaicAnnotation {
                        moveMosaicToFront(at: topIndex)
                    }
                }
            }
            delegate?.selectionChanged(selectedAnnotationIndex)
            needsDisplay = true
            return
        }

        if selectedTool == .text {
            delegate?.textTapped(at: point)
            return
        }

        // 色を完全にコピーして使用（SwiftUI状態への参照を断ち切る）
        let safeColor = (selectedColor.copy() as? NSColor) ?? .systemRed

        switch selectedTool {
        case .move:
            break
        case .pen:
            currentAnnotation = FreehandAnnotation(points: [point], color: safeColor, lineWidth: lineWidth, isHighlighter: false, strokeEnabled: strokeEnabled)
        case .highlight:
            currentAnnotation = FreehandAnnotation(points: [point], color: safeColor, lineWidth: lineWidth, isHighlighter: true, strokeEnabled: strokeEnabled)
        case .line:
            currentAnnotation = LineAnnotation(startPoint: point, endPoint: point, color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .arrow:
            currentAnnotation = ArrowAnnotation(startPoint: point, endPoint: point, color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .arrowText:
            currentAnnotation = ArrowAnnotation(startPoint: point, endPoint: point, color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .rectangle:
            currentAnnotation = RectAnnotation(rect: CGRect(origin: point, size: .zero), color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .ellipse:
            currentAnnotation = EllipseAnnotation(rect: CGRect(origin: point, size: .zero), color: safeColor, lineWidth: lineWidth, strokeEnabled: strokeEnabled)
        case .text:
            break
        case .mosaic:
            // 太さ1→2, 太さ5→8, 太さ10→14 くらいの緩やかな変化
            currentAnnotation = MosaicAnnotation(rect: CGRect(origin: point, size: .zero), pixelSize: max(Int(lineWidth * 1.2 + 1), 2), sourceImage: sourceImage)
        case .textSelection, .trim:
            break
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }

        let point = imagePoint(from: event)

        // トリミングモードの場合
        if selectedTool == .trim, let start = trimDragStart {
            trimRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            needsDisplay = true
            return
        }

        // リサイズ中の場合
        if isResizing, let index = selectedAnnotationIndex, index < annotations.count {
            // Shift押下時、rectangle/ellipseは対角アンカー基準の正方形に補正
            var resizePoint = point
            if event.modifierFlags.contains(.shift) {
                let original: CGRect? = {
                    if let rect = annotations[index] as? RectAnnotation { return rect.rect }
                    if let ellipse = annotations[index] as? EllipseAnnotation { return ellipse.rect }
                    return nil
                }()
                if let original = original {
                    resizePoint = AnnotationGeometry.squareConstrainedResizePoint(point: point, original: original, handle: activeResizeHandle)
                }
            }
            resizeAnnotation(at: index, to: resizePoint)
            needsDisplay = true
            return
        }

        // 移動モードで選択中のアノテーションがある場合
        if selectedTool == .move, let index = selectedAnnotationIndex, let lastPoint = lastDragPoint {
            let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
            annotations[index].move(by: delta)
            lastDragPoint = point
            didMoveAnnotation = true
            needsDisplay = true
            return
        }

        guard let start = dragStart else { return }

        // Shift押下時、rectangle/ellipseのみ始点基準の正方形（=正円）に補正
        let effectiveEnd: CGPoint = {
            guard event.modifierFlags.contains(.shift),
                  selectedTool == .rectangle || selectedTool == .ellipse else {
                return point
            }
            let dx = point.x - start.x
            let dy = point.y - start.y
            let size = max(abs(dx), abs(dy))
            return CGPoint(
                x: start.x + (dx >= 0 ? size : -size),
                y: start.y + (dy >= 0 ? size : -size)
            )
        }()

        let newRect = CGRect(
            x: min(start.x, effectiveEnd.x),
            y: min(start.y, effectiveEnd.y),
            width: abs(effectiveEnd.x - start.x),
            height: abs(effectiveEnd.y - start.y)
        )

        switch selectedTool {
        case .move:
            break
        case .pen, .highlight:
            if let freehand = currentAnnotation as? FreehandAnnotation {
                freehand.addPoint(point)
            }
        case .line:
            if let line = currentAnnotation as? LineAnnotation {
                line.endPoint = point
            }
        case .arrow, .arrowText:
            if let arrow = currentAnnotation as? ArrowAnnotation {
                arrow.endPoint = point
            }
        case .rectangle:
            if let rect = currentAnnotation as? RectAnnotation {
                rect.rect = newRect
            }
        case .ellipse:
            if let ellipse = currentAnnotation as? EllipseAnnotation {
                ellipse.rect = newRect
            }
        case .text:
            break
        case .mosaic:
            if let mosaic = currentAnnotation as? MosaicAnnotation {
                mosaic.rect = newRect
            }
        case .textSelection, .trim:
            break
        }
        delegate?.currentAnnotationUpdated(currentAnnotation)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }

        // トリミングモードの場合
        if selectedTool == .trim {
            trimDragStart = nil
            // 小さすぎる矩形（10px未満）はクリア
            if let rect = trimRect, rect.width < 10 || rect.height < 10 {
                trimRect = nil
            }
            needsDisplay = true
            return
        }

        // リサイズ終了
        if isResizing {
            isResizing = false
            activeResizeHandle = .none
            delegate?.annotationMoved()
            needsDisplay = true
            return
        }

        // 移動モードでアノテーションを移動した場合（選択は保持）
        if selectedTool == .move && selectedAnnotationIndex != nil {
            // 実際に移動した場合のみ保存
            if didMoveAnnotation {
                delegate?.annotationMoved()
                didMoveAnnotation = false
            }
            lastDragPoint = nil
            needsDisplay = true
            return
        }

        if let annotation = currentAnnotation {
            // 矢印文字ツールの場合：テキスト入力を開始（矢印はコールバック側で追加）
            if selectedTool == .arrowText, let arrow = annotation as? ArrowAnnotation {
                delegate?.arrowTextDragFinished(startPoint: arrow.startPoint, endPoint: arrow.endPoint)
                currentAnnotation = nil
                dragStart = nil
                needsDisplay = true
                return
            }
            // モザイクの場合はドラッグ終了フラグを設定
            if let mosaic = annotation as? MosaicAnnotation {
                mosaic.isDrawing = false
            }
            delegate?.annotationAdded(annotation)
        }
        currentAnnotation = nil
        dragStart = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete (51) または Backspace (117) キー
        if event.keyCode == 51 || event.keyCode == 117 {
            if selectedAnnotationIndex != nil {
                delegate?.deleteSelectedAnnotation()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    /// アノテーションのリサイズ処理
    private func resizeAnnotation(at index: Int, to point: CGPoint) {
        let annotation = annotations[index]

        if let line = annotation as? LineAnnotation {
            switch activeResizeHandle {
            case .startPoint:
                line.startPoint = point
            case .endPoint:
                line.endPoint = point
            default: break
            }
        } else if let arrow = annotation as? ArrowAnnotation {
            switch activeResizeHandle {
            case .startPoint:
                arrow.startPoint = point
            case .endPoint:
                arrow.endPoint = point
            default:
                break
            }
        } else if let rect = annotation as? RectAnnotation {
            rect.rect = AnnotationGeometry.resizedRect(original: rect.rect, handle: activeResizeHandle, to: point)
        } else if let ellipse = annotation as? EllipseAnnotation {
            ellipse.rect = AnnotationGeometry.resizedRect(original: ellipse.rect, handle: activeResizeHandle, to: point)
        } else if let mosaic = annotation as? MosaicAnnotation {
            mosaic.rect = AnnotationGeometry.resizedRect(original: mosaic.rect, handle: activeResizeHandle, to: point)
            mosaic.clearCache()
        }
    }

    // resizedRect / squareConstrainedResizePoint は Mas/Logic/AnnotationGeometry.swift に移動済み

    // ぼかしを最背面（インデックス0）に移動
    private func moveMosaicToBack(at index: Int) {
        guard index < annotations.count, annotations[index] is MosaicAnnotation else { return }
        let mosaic = annotations.remove(at: index)
        annotations.insert(mosaic, at: 0)
        delegate?.annotationMoved()
    }

    // ぼかしを最前面（配列の最後）に移動
    private func moveMosaicToFront(at index: Int) {
        guard index < annotations.count, annotations[index] is MosaicAnnotation else { return }
        let mosaic = annotations.remove(at: index)
        annotations.append(mosaic)
        selectedAnnotationIndex = annotations.count - 1
        delegate?.annotationMoved()
    }

    // MARK: - トリミング右クリックメニュー

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectedTool == .trim, let trimRect = trimRect,
              trimRect.width >= 10, trimRect.height >= 10 else {
            return nil
        }

        let menu = NSMenu()
        let trimItem = NSMenuItem(title: "トリミング", action: #selector(executeTrim), keyEquivalent: "")
        trimItem.target = self
        menu.addItem(trimItem)

        let copyItem = NSMenuItem(title: "コピー", action: #selector(executeCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        return menu
    }

    @objc private func executeTrim() {
        guard let trimRect = trimRect else { return }
        delegate?.trimRequested(rect: trimRect)
        self.trimRect = nil
        needsDisplay = true
    }

    @objc private func executeCopy() {
        guard let trimRect = trimRect else { return }
        delegate?.copyTrimRegionRequested(rect: trimRect)
    }

    @objc private func cancelTrim() {
        trimRect = nil
        needsDisplay = true
    }
}

