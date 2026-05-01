import CoreGraphics

// リサイズハンドルの位置
enum ResizeHandle {
    case none
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight
    case startPoint, endPoint  // 矢印用
}

/// アノテーション図形の純粋幾何計算。
enum AnnotationGeometry {

    /// 既存矩形をリサイズハンドルとマウス座標から再計算する。
    /// - 座標系: NSView のフリップ座標（Y軸下向き）を前提とする
    static func resizedRect(original: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
        var newRect = original

        switch handle {
        case .topLeft:
            // 左上ハンドル: 左上コーナーをマウス位置に移動
            newRect = CGRect(
                x: point.x,
                y: point.y,
                width: original.maxX - point.x,
                height: original.maxY - point.y
            )
        case .topRight:
            // 右上ハンドル: 右上コーナーをマウス位置に移動
            newRect = CGRect(
                x: original.minX,
                y: point.y,
                width: point.x - original.minX,
                height: original.maxY - point.y
            )
        case .bottomLeft:
            // 左下ハンドル: 左下コーナーをマウス位置に移動
            newRect = CGRect(
                x: point.x,
                y: original.minY,
                width: original.maxX - point.x,
                height: point.y - original.minY
            )
        case .bottomRight:
            // 右下ハンドル: 右下コーナーをマウス位置に移動
            newRect = CGRect(
                x: original.minX,
                y: original.minY,
                width: point.x - original.minX,
                height: point.y - original.minY
            )
        case .top:
            // 上辺ハンドル: Y座標と高さを変更
            newRect = CGRect(
                x: original.minX,
                y: point.y,
                width: original.width,
                height: original.maxY - point.y
            )
        case .bottom:
            // 下辺ハンドル: 高さのみ変更
            newRect = CGRect(
                x: original.minX,
                y: original.minY,
                width: original.width,
                height: point.y - original.minY
            )
        case .left:
            // 左辺ハンドル: X座標と幅を変更
            newRect = CGRect(
                x: point.x,
                y: original.minY,
                width: original.maxX - point.x,
                height: original.height
            )
        case .right:
            // 右辺ハンドル: 幅のみ変更
            newRect = CGRect(
                x: original.minX,
                y: original.minY,
                width: point.x - original.minX,
                height: original.height
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

    /// 直線の bounding rect。指定したパディングを含む。
    /// - Parameter lineWidth: 線幅（パディングは lineWidth / 2 として計算）
    static func lineBoundingRect(startPoint: CGPoint, endPoint: CGPoint, lineWidth: CGFloat) -> CGRect {
        let pad = lineWidth / 2
        return CGRect(
            x: min(startPoint.x, endPoint.x) - pad,
            y: min(startPoint.y, endPoint.y) - pad,
            width: abs(endPoint.x - startPoint.x) + pad * 2,
            height: abs(endPoint.y - startPoint.y) + pad * 2
        )
    }

    /// 直線の bounding rect。明示的なパディングを指定する。
    /// - Parameter padding: 各辺に加えるパディング量
    static func lineBoundingRect(startPoint: CGPoint, endPoint: CGPoint, padding: CGFloat) -> CGRect {
        return CGRect(
            x: min(startPoint.x, endPoint.x) - padding,
            y: min(startPoint.y, endPoint.y) - padding,
            width: abs(endPoint.x - startPoint.x) + padding * 2,
            height: abs(endPoint.y - startPoint.y) + padding * 2
        )
    }
}
