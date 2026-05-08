import AppKit
import CoreGraphics

/// CGEventTap で受信したマウス／キーイベントの種別。座標はグローバル CG 座標。
enum MouseEventTapEvent {
    case mouseDown(at: CGPoint)
    case mouseDragged(to: CGPoint)
    case mouseUp(at: CGPoint)
    case mouseMoved(to: CGPoint)
    case escKeyDown
}

/// マウスイベントを横取りするタップのプロトコル。
///
/// CGEventTap を session-level / consuming 設定で生成し、
/// 他アプリ（特に NSMenu のトラッキングループ）にイベントを届けないようにする。
protocol MouseEventTapping: AnyObject {
    /// タップを開始する。`handler` は受信したイベントを処理するクロージャ。
    /// アクセシビリティ権限がない場合や CGEventTap 生成に失敗した場合は false を返す。
    func install(handler: @escaping (MouseEventTapEvent) -> Void) -> Bool

    /// タップを破棄する。
    func uninstall()
}

/// CGEventTap を用いた本番実装。
/// アクセシビリティ権限が許可されていることが前提。
final class MouseEventTap: MouseEventTapping {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((MouseEventTapEvent) -> Void)?

    deinit { uninstall() }

    func install(handler: @escaping (MouseEventTapEvent) -> Void) -> Bool {
        // 既に install 済みなら一度破棄して上書き
        uninstall()
        self.handler = handler

        // 横取りしたいイベントのマスク
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        // self への弱参照を userInfo として渡す
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // .defaultTap = 消費可能（NSMenu に届かない）
            eventsOfInterest: mask,
            callback: MouseEventTap.tapCallback,
            userInfo: unmanagedSelf
        ) else {
            self.handler = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func uninstall() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
    }

    // MARK: - C 関数として渡せる static callback

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()

        // システムが tap を無効化した場合の自己回復
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let active = tap.eventTap {
                CGEvent.tapEnable(tap: active, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        switch type {
        case .leftMouseDown:
            tap.handler?(.mouseDown(at: location))
            return nil  // 消費して NSMenu などに届けない
        case .leftMouseDragged:
            tap.handler?(.mouseDragged(to: location))
            return nil
        case .leftMouseUp:
            tap.handler?(.mouseUp(at: location))
            return nil
        case .mouseMoved:
            tap.handler?(.mouseMoved(to: location))
            return nil
        case .keyDown:
            // ESC のみ拾う。他のキーは透過させる
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 {
                tap.handler?(.escKeyDown)
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
