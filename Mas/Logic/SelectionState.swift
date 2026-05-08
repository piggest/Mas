import CoreGraphics

/// CGEventTap 駆動の範囲選択における座標追跡ロジック。
///
/// 旧実装は SelectionView の mouseDown/mouseDragged/mouseUp に状態を持っていたが、
/// CGEventTap でグローバルマウスイベントを横取りする方式では、
/// イベントの受信箇所と描画箇所（per-screen の panel）が分離するため、
/// 状態管理を純粋ロジックとして抽出してテスト可能にした。
///
/// 座標系: グローバル CG 座標（プライマリディスプレイ左上原点、Y 下方向）。
/// CGEvent.location() が返す座標と一致する。
struct SelectionState {
    private(set) var startPoint: CGPoint?
    private(set) var currentPoint: CGPoint?

    /// ドラッグ中の選択範囲。ドラッグ方向に関わらず正規化された rect を返す。
    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    /// ドラッグ開始。start/current を同一点で初期化する。
    mutating func begin(at point: CGPoint) {
        startPoint = point
        currentPoint = point
    }

    /// 現在位置を更新する。
    mutating func update(to point: CGPoint) {
        currentPoint = point
    }

    /// 状態をクリアする。
    mutating func reset() {
        startPoint = nil
        currentPoint = nil
    }

    /// ドラッグ距離が threshold 以下ならクリック扱い。
    /// トラックパッドの微小ドラッグをクリックとして処理するために使う。
    func isClickGesture(threshold: CGFloat) -> Bool {
        guard let start = startPoint, let current = currentPoint else { return true }
        return hypot(current.x - start.x, current.y - start.y) <= threshold
    }
}
