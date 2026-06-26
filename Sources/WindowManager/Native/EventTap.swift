import CoreGraphics
import Foundation

/// キーイベント 1 件分の情報（Ruby ハンドラへ渡す）。
struct KeyEvent {
    let keyCode: Int64
    /// CGEventFlags の生値（修飾キー判定に使う）。
    let flags: UInt64
    let isKeyDown: Bool
}

/// グローバルキーイベントタップ（Part A の §5）。
///
/// キーイベントごとに `onKey` を呼び、戻り値が `true` ならイベントを **握りつぶす**
/// （他アプリへ渡さない＝リマップ）。`false` なら通常通り通す。
/// `onKey` は同期的に高速に返すこと（タップコールバックはブロックできない）。
final class EventTap {
    typealias Handler = (KeyEvent) -> Bool

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onKey: Handler

    init(onKey: @escaping Handler) {
        self.onKey = onKey
    }

    /// タップを設置してメイン run loop に載せる。要アクセシビリティ権限。
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        // self を userInfo として渡す（Unmanaged 経由でコールバックから取り出す）。
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// タップがタイムアウト等で無効化された場合に再有効化する。
    func reenable() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// コールバックから呼ばれる本体。
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // タイムアウト/ユーザ入力で無効化されたら再有効化して素通し。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return Unmanaged.passUnretained(event)
        }

        let keyEvent = KeyEvent(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags.rawValue,
            isKeyDown: (type == .keyDown)
        )

        let consume = onKey(keyEvent)
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}

/// C 関数ポインタ互換のトップレベルコールバック。
private func eventTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
