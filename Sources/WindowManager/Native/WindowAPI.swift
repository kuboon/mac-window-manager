#if canImport(AppKit)
import AppKit
import ApplicationServices
import CoreGraphics

/// CGWindowID から対応する AXUIElement を引くための private API。
/// 公開 API には CGWindowID ↔ AXUIElement の対応付けが無いため、yabai 等の
/// 主要ウィンドウマネージャと同様にこの private シンボルを利用する。
/// （OS 更新で消える可能性は低いが、private である点は理解の上で使用すること）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Ruby に渡すウィンドウ情報（JSON 化される）。座標は top-left 原点。
struct WindowInfo: Codable {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let title: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let layer: Int
    let onScreen: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, x, y, w, h, layer
        case onScreen = "on_screen"
    }
}

/// macOS のウィンドウ列挙・操作 API のラッパ（Part A の §1, §2 を実装）。
/// 全メソッドはメインスレッドで呼ぶこと（AX/AppKit の制約）。
enum WindowAPI {

    // MARK: - 列挙（CoreGraphics Window Services）

    /// オンスクリーンの通常ウィンドウ一覧を返す。タイトルは画面収録権限が無いと空になる。
    static func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any]
            else { return nil }

            var bounds = CGRect.zero
            _ = CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &bounds)

            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            // レイヤ 0 = 通常アプリのウィンドウ。メニューバー/Dock 等を除外。
            guard layer == 0 else { return nil }

            return WindowInfo(
                id: id,
                pid: pid,
                app: dict[kCGWindowOwnerName as String] as? String ?? "",
                title: dict[kCGWindowName as String] as? String ?? "",
                x: bounds.origin.x, y: bounds.origin.y,
                w: bounds.size.width, h: bounds.size.height,
                layer: layer,
                onScreen: (dict[kCGWindowIsOnscreen as String] as? Bool) ?? false
            )
        }
    }

    // MARK: - 操作（Accessibility）

    /// 指定ウィンドウを (x, y)（top-left 原点, グローバル座標）へ移動する。
    @discardableResult
    static func move(windowID: CGWindowID, x: Double, y: Double) -> Bool {
        guard let win = axWindow(for: windowID) else { return false }
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, value) == .success
    }

    /// 指定ウィンドウのサイズを (w, h) に設定する。
    @discardableResult
    static func resize(windowID: CGWindowID, w: Double, h: Double) -> Bool {
        guard let win = axWindow(for: windowID) else { return false }
        var size = CGSize(width: w, height: h)
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, value) == .success
    }

    /// 指定ウィンドウを前面へ。
    @discardableResult
    static func raise(windowID: CGWindowID) -> Bool {
        guard let win = axWindow(for: windowID) else { return false }
        return AXUIElementPerformAction(win, kAXRaiseAction as CFString) == .success
    }

    /// 指定ウィンドウの最小化状態を設定する。
    @discardableResult
    static func minimize(windowID: CGWindowID, _ minimized: Bool) -> Bool {
        guard let win = axWindow(for: windowID) else { return false }
        let value = minimized ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, value!) == .success
    }

    /// 現在フォーカスされているウィンドウの CGWindowID を返す。
    static func focusedWindowID() -> CGWindowID? {
        let system = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else { return nil }
        let appElement = app as! AXUIElement

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else { return nil }
        let winElement = window as! AXUIElement

        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(winElement, &id) == .success else { return nil }
        return id
    }

    // MARK: - CGWindowID → AXUIElement 解決

    /// CGWindowID に対応する AX ウィンドウ要素を引く。
    /// pid をたどってアプリ要素を作り、その全ウィンドウを走査して _AXUIElementGetWindow で照合する。
    private static func axWindow(for windowID: CGWindowID) -> AXUIElement? {
        guard let pid = pid(for: windowID) else { return nil }
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return nil }

        for win in windows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(win, &id) == .success, id == windowID {
                return win
            }
        }
        return nil
    }

    /// CGWindowID から所有プロセスの pid を引く。
    private static func pid(for windowID: CGWindowID) -> pid_t? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let raw = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let dict = raw.first,
              let pid = dict[kCGWindowOwnerPID as String] as? pid_t
        else { return nil }
        return pid
    }
}
#endif
