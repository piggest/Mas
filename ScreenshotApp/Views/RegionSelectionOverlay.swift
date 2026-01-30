import AppKit
import SwiftUI

class RegionSelectionOverlay {
    private var overlayWindows: [NSWindow] = []
    private var selectionView: SelectionView?
    private let onComplete: (CGRect) -> Void
    private static var currentOverlay: RegionSelectionOverlay?

    init(onComplete: @escaping (CGRect) -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        RegionSelectionOverlay.currentOverlay = self

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar + 1
            window.backgroundColor = NSColor.clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                self?.handleSelection(rect, on: screen)
            } onCancel: { [weak self] in
                self?.dismiss()
            }

            window.contentView = selectionView
            self.selectionView = selectionView

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(selectionView)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    private func handleSelection(_ rect: CGRect, on screen: NSScreen) {
        // rectはすでに左上原点の座標（isFlipped = true）
        // スクリーン上のグローバル座標に変換（左上原点のまま）
        let globalRect = CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: rect.origin.y,  // 左上原点なのでそのまま
            width: rect.width,
            height: rect.height
        )

        dismiss()
        onComplete(globalRect)
    }

    private func dismiss() {
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        RegionSelectionOverlay.currentOverlay = nil
    }
}

class SelectionView: NSView {
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectionRect: CGRect?
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    // 左上原点に変更（画像座標系と一致させる）
    override var isFlipped: Bool { true }

    init(frame: NSRect, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateSelectionRect()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect, rect.width > 10, rect.height > 10 else {
            onCancel()
            return
        }
        onComplete(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }

    private func updateSelectionRect() {
        guard let start = startPoint, let current = currentPoint else { return }

        selectionRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 半透明の黒でオーバーレイ
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }

        // 選択領域を透明にする（くり抜き効果）
        NSColor.clear.set()
        rect.fill(using: .copy)

        // 選択領域の枠線
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // 破線のボーダー
        let dashPath = NSBezierPath(rect: rect)
        dashPath.lineWidth = 2
        NSColor.systemBlue.setStroke()
        dashPath.setLineDash([5, 5], count: 2, phase: 0)
        dashPath.stroke()

        // サイズ表示
        drawDimensions(for: rect)
    }

    private func drawDimensions(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]

        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 6

        // isFlipped = true なので、rectの下にラベルを表示
        var labelRect = CGRect(
            x: rect.midX - size.width / 2 - padding,
            y: rect.maxY + 8,
            width: size.width + padding * 2,
            height: size.height + padding
        )

        // ラベルが画面外に出ないように調整
        if labelRect.maxY > bounds.maxY - 10 {
            labelRect.origin.y = rect.minY - labelRect.height - 8
        }

        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()

        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + padding, y: labelRect.minY + padding / 2),
            withAttributes: attributes
        )
    }
}
