import CoreGraphics

// リサイズハンドルの位置
enum ResizeHandle {
    case none
    case topLeft, topRight, bottomLeft, bottomRight
    case startPoint, endPoint  // 矢印用
}

/// アノテーション図形の純粋幾何計算。
/// 既存の `AnnotationCanvas` 内ロジックをそのまま enum に切り出したもの。
/// 挙動同等性を最優先しているため、計算式はオリジナルと完全一致。
enum AnnotationGeometry {

    /// 既存矩形をリサイズハンドルとマウス座標から再計算する。
    /// `AnnotationCanvas` 内で使われていた既存実装をそのまま移植。
    static func resizedRect(original: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var newRect = original

        switch handle {
        case .topLeft:
            newRect = CGRect(
                x: point.x,
                y: original.minY,
                width: original.maxX - point.x,
                height: point.y - original.minY
            )
        case .topRight:
            newRect = CGRect(
                x: original.minX,
                y: original.minY,
                width: point.x - original.minX,
                height: point.y - original.minY
            )
        case .bottomLeft:
            newRect = CGRect(
                x: point.x,
                y: point.y,
                width: original.maxX - point.x,
                height: original.maxY - point.y
            )
        case .bottomRight:
            newRect = CGRect(
                x: original.minX,
                y: point.y,
                width: point.x - original.minX,
                height: original.maxY - point.y
            )
        default:
            break
        }

        // 最小サイズを保証（幅・高さが負にならないように正規化）
        let minSize: CGFloat = 10
        if newRect.width < minSize || newRect.height < minSize {
            return CGRect(
                x: min(newRect.minX, newRect.maxX),
                y: min(newRect.minY, newRect.maxY),
                width: max(abs(newRect.width), minSize),
                height: max(abs(newRect.height), minSize)
            )
        }

        return newRect
    }

    /// Shift 押下時、対角アンカーを固定して正方形になるよう座標を補正する。
    static func squareConstrainedResizePoint(point: CGPoint, original: CGRect, handle: ResizeHandle) -> CGPoint {
        let anchor: CGPoint
        switch handle {
        case .topLeft:     anchor = CGPoint(x: original.maxX, y: original.minY)
        case .topRight:    anchor = CGPoint(x: original.minX, y: original.minY)
        case .bottomLeft:  anchor = CGPoint(x: original.maxX, y: original.maxY)
        case .bottomRight: anchor = CGPoint(x: original.minX, y: original.maxY)
        default: return point
        }
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let size = max(abs(dx), abs(dy))
        return CGPoint(
            x: anchor.x + (dx >= 0 ? size : -size),
            y: anchor.y + (dy >= 0 ? size : -size)
        )
    }

    /// 直線の bounding rect。指定したパディングを各辺に加算する。
    static func lineBoundingRect(startPoint: CGPoint, endPoint: CGPoint, padding: CGFloat) -> CGRect {
        let minX = min(startPoint.x, endPoint.x) - padding
        let minY = min(startPoint.y, endPoint.y) - padding
        let maxX = max(startPoint.x, endPoint.x) + padding
        let maxY = max(startPoint.y, endPoint.y) + padding
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
