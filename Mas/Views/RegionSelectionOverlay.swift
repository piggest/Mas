import AppKit
import SwiftUI

class RegionSelectionOverlay {
    private var overlayWindows: [NSWindow] = []
    private var selectionEntries: [(screen: NSScreen, view: SelectionView)] = []
    private var dragOriginScreen: NSScreen?
    private var escMonitor: Any?
    private let accessibility: AccessibilityChecking
    private let eventTap: MouseEventTapping
    private let onComplete: (CGRect) -> Void
    private let onCancel: (() -> Void)?
    private static var currentOverlay: RegionSelectionOverlay?

    init(
        accessibility: AccessibilityChecking = SystemAccessibility(),
        eventTap: MouseEventTapping = MouseEventTap(),
        onComplete: @escaping (CGRect) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.accessibility = accessibility
        self.eventTap = eventTap
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func show() {
        RegionSelectionOverlay.currentOverlay = self

        for screen in NSScreen.screens {
            let panel = OverlayWindowFactory.makeOverlayPanel(for: screen)

            let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                self?.handleSelection(rect, on: screen)
            } onCancel: { [weak self] in
                self?.dismiss(cancelled: true)
            }

            panel.contentView = selectionView
            panel.orderFrontRegardless()
            overlayWindows.append(panel)
            selectionEntries.append((screen, selectionView))
        }

        // メイン経路: アクセシビリティ権限がある → CGEventTap で他アプリ（NSMenu の
        // メニュートラッキングループ含む）に届く前にマウスイベントを横取りする。
        // これで右クリックメニューを表示したまま範囲選択ドラッグできる。
        let installed = accessibility.isTrusted() && installEventTap()

        if !installed {
            // フォールバック: AX 未許可。NSPanel 上のクリックでドラッグするモード。
            // 右クリックメニュー保持はできない（macOS の制約）。
            // パネルへのマウスイベント受信を有効化する。
            for window in overlayWindows {
                window.ignoresMouseEvents = false
            }
            // ESC は NSEvent local monitor で受ける（パネル non-key のため keyDown は届かない）
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.dismiss(cancelled: true)
                    return nil
                }
                return event
            }

            // 初回のみ AX 許可を要求（システムの権限ダイアログを出す）。
            // 次回起動時に許可済みなら CGEventTap が使えるようになる。
            _ = accessibility.requestAccessibility()
        } else {
            // CGEventTap でイベント横取りするので、パネル自体はマウスを受け取らない
            for window in overlayWindows {
                window.ignoresMouseEvents = true
            }
        }

        NSCursor.crosshair.push()
    }

    private func installEventTap() -> Bool {
        return eventTap.install { [weak self] event in
            // tap callback は別スレッド（CGEventTap の RunLoop）から呼ばれる可能性があるため
            // UI 操作は main にディスパッチ
            DispatchQueue.main.async {
                self?.handleTapEvent(event)
            }
        }
    }

    private func handleTapEvent(_ event: MouseEventTapEvent) {
        switch event {
        case .mouseDown(let point):
            guard let entry = entry(forGlobalPoint: point) else { return }
            dragOriginScreen = entry.screen
            entry.view.externalBeginSelection(at: viewPoint(from: point, screen: entry.screen))
        case .mouseDragged(let point):
            guard let originScreen = dragOriginScreen,
                  let entry = entry(forScreen: originScreen) else { return }
            entry.view.externalUpdateSelection(to: viewPoint(from: point, screen: entry.screen))
        case .mouseUp(let point):
            guard let originScreen = dragOriginScreen,
                  let entry = entry(forScreen: originScreen) else { return }
            entry.view.externalEndSelection(at: viewPoint(from: point, screen: entry.screen))
            dragOriginScreen = nil
        case .mouseMoved:
            // ドラッグ中以外のマウス移動は今は使わない（描画に必要なら拡張）
            break
        case .escKeyDown:
            dismiss(cancelled: true)
        }
    }

    /// グローバル CG 座標を含むスクリーンのエントリを返す。
    private func entry(forGlobalPoint point: CGPoint) -> (screen: NSScreen, view: SelectionView)? {
        return selectionEntries.first { $0.screen.cgFrame.contains(point) }
    }

    private func entry(forScreen screen: NSScreen) -> (screen: NSScreen, view: SelectionView)? {
        return selectionEntries.first { $0.screen === screen }
    }

    /// グローバル CG 座標 → 指定スクリーン上の SelectionView ローカル座標（左上原点）。
    private func viewPoint(from globalPoint: CGPoint, screen: NSScreen) -> CGPoint {
        let cgFrame = screen.cgFrame
        return CGPoint(
            x: globalPoint.x - cgFrame.origin.x,
            y: globalPoint.y - cgFrame.origin.y
        )
    }

    private func handleSelection(_ rect: CGRect, on screen: NSScreen) {
        // rectはビュー内の左上原点座標（isFlipped = true）
        // CGグローバル座標（左上原点）に変換
        // スクリーンの左上のCG座標 = primaryHeight - screen.NS_y - screen.height
        let screenTopInCG = NSScreen.primaryScreenHeight - screen.frame.origin.y - screen.frame.height
        let globalRect = CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: screenTopInCG + rect.origin.y,
            width: rect.width,
            height: rect.height
        )

        dismiss()
        onComplete(globalRect)
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    /// テスト用: 外部から強制 dismiss するためのフック。本番コードからは使わない。
    func cancelForTest() {
        dismiss(cancelled: true)
    }

    private func dismiss(cancelled: Bool = false) {
        eventTap.uninstall()
        removeEscMonitor()
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        selectionEntries.removeAll()
        dragOriginScreen = nil
        RegionSelectionOverlay.currentOverlay = nil
        if cancelled {
            onCancel?()
        }
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

    // パネルが key/main にならない（NSMenu を保つため）状態でも、
    // 最初のクリックを「ドラッグ開始」として処理するために必須。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        externalBeginSelection(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        externalUpdateSelection(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        externalEndSelection(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - 外部駆動API（CGEventTap 経由でグローバル座標を変換した結果を受け取る）

    /// 選択開始。CGEventTap callback もしくはローカル mouseDown から呼ばれる。
    /// `viewPoint` はビュー内ローカル座標（左上原点）。
    func externalBeginSelection(at viewPoint: CGPoint) {
        startPoint = viewPoint
        currentPoint = viewPoint
        selectionRect = nil
        needsDisplay = true
    }

    func externalUpdateSelection(to viewPoint: CGPoint) {
        currentPoint = viewPoint
        updateSelectionRect()
        needsDisplay = true
    }

    func externalEndSelection(at viewPoint: CGPoint) {
        // startPoint との距離でクリック/ドラッグを判定（トラックパッドの微小ドラッグ対策）
        let isClick: Bool
        if let start = startPoint {
            isClick = hypot(viewPoint.x - start.x, viewPoint.y - start.y) <= 20
        } else {
            isClick = true
        }

        // ドラッグで十分な大きさの選択範囲がある場合はそのまま使用
        if !isClick, let rect = selectionRect, rect.width > 5, rect.height > 5 {
            onComplete(rect)
            return
        }

        // クリックの場合、その位置にあるウィンドウを検出
        if let windowRect = findWindowAtPoint(viewPoint) {
            onComplete(windowRect)
        } else {
            onCancel()
        }
    }

    private func findWindowAtPoint(_ point: CGPoint) -> CGRect? {
        // ビュー座標をCGグローバル座標に変換（左上原点）
        guard let screen = window?.screen else { return nil }
        let screenTopInCG = NSScreen.primaryScreenHeight - screen.frame.origin.y - screen.frame.height
        let screenPoint = CGPoint(
            x: screen.frame.origin.x + point.x,
            y: screenTopInCG + point.y
        )

        // ウィンドウリストを取得
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                continue
            }

            // 自分自身のアプリとオーバーレイは除外
            if ownerName == "Mas" { continue }

            // 小さすぎるウィンドウは除外
            guard width > 50 && height > 50 else { continue }

            let windowRect = CGRect(x: x, y: y, width: width, height: height)

            // クリック位置がウィンドウ内にあるか確認
            if windowRect.contains(screenPoint) {
                // CGグローバル座標からビュー座標に逆変換
                // （handleSelectionがビュー→CGグローバル変換するため）
                return CGRect(
                    x: windowRect.origin.x - screen.frame.origin.x,
                    y: windowRect.origin.y - screenTopInCG,
                    width: windowRect.width,
                    height: windowRect.height
                )
            }
        }

        return nil
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
        guard let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium) as NSFont? else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: NSColor.white as Any
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
