#if canImport(AppKit)
import AppKit
import ApplicationServices
import CoreGraphics

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

/// `set_frame` の結果（実際に落ち着いた矩形）。要求どおりにならないことがあるので返す。
struct FrameInfo: Codable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        w = rect.size.width
        h = rect.size.height
    }
}

/// macOS のウィンドウ列挙・操作 API のラッパ。
///
/// **スレッド方針**: 列挙（CGWindowList）は WindowServer との通信なのでメインスレッドで行う。
/// 一方 **Accessibility の呼び出しは対象アプリの応答を待つ**ため、必ず `AXThreadPool` 経由で
/// pid ごとの専用スレッドへ逃がし、タイムアウトを付ける。取得できなかった場合は `nil`/`false`
/// を返し、ウィンドウマネージャ全体は止めない。
enum WindowAPI {

    // MARK: - 列挙（CoreGraphics Window Services）

    /// 通常ウィンドウ一覧を返す（レイヤ 0 のみ）。タイトルは画面収録権限が無いと空になる。
    /// - `all: false`（既定）… オンスクリーンの窓のみ。最小化中・非表示アプリの窓は含まない。
    /// - `all: true` … 最小化中・非表示アプリ・別 Space の窓も含む全列挙。
    ///   最小化かどうかの判定は CG からは取れないので、Ruby 側（wm.rb の `WM.all_windows`）が
    ///   `minimizedWindowIDs(pid:)` と突き合わせて行う（ポリシーは Ruby に置く方針）。
    static func listWindows(all: Bool = false) -> [WindowInfo] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        options.insert(all ? .optionAll : .optionOnScreenOnly)
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { info(from: $0) }
    }

    /// 指定アプリ（pid）の最小化中ウィンドウの CGWindowID 一覧を返す薄いプリミティブ。
    /// AX のウィンドウリストは最小化中の窓も含むので、`kAXMinimizedAttribute` で拾える。
    static func minimizedWindowIDs(pid: pid_t) -> [CGWindowID] {
        AXThreadPool.run(pid: pid) {
            appWindows(pid: pid).compactMap { win -> CGWindowID? in
                var minRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
                      (minRef as? Bool) == true else { return nil }
                return PrivateAPI.windowID(of: win)
            }
        } ?? []
    }

    /// CGWindowList の 1 エントリを WindowInfo へ変換する（レイヤ 0 以外は nil）。
    private static func info(from dict: [String: Any]) -> WindowInfo? {
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

    // MARK: - 操作（Accessibility）

    /// 指定ウィンドウを (x, y)（top-left 原点, グローバル座標）へ移動する。
    @discardableResult
    static func move(windowID: CGWindowID, x: Double, y: Double) -> Bool {
        withWindow(windowID) { window, pid in
            withEnhancedUIDisabled(pid: pid) {
                setPosition(window, CGPoint(x: x, y: y))
            }
        } ?? false
    }

    /// 指定ウィンドウのサイズを (w, h) に設定する。
    @discardableResult
    static func resize(windowID: CGWindowID, w: Double, h: Double) -> Bool {
        withWindow(windowID) { window, pid in
            withEnhancedUIDisabled(pid: pid) {
                setSize(window, CGSize(width: w, height: h))
            }
        } ?? false
    }

    /// 位置とサイズを 1 回の AX 往復でまとめて当て、**実際に落ち着いた矩形**を返す。
    ///
    /// `move` + `resize` を別々に呼ぶより望ましい:
    ///   - AX スレッドへの往復が 1 回で済む
    ///   - `AXEnhancedUserInterface` の退避/復帰も 1 回で済む
    ///   - 「移動 → リサイズ → 再度移動」の順で当てるので、リサイズ時にディスプレイ境界へ
    ///     押し戻される定番の症状を吸収できる
    static func setFrame(windowID: CGWindowID, x: Double, y: Double, w: Double, h: Double) -> FrameInfo? {
        let target = CGRect(x: x, y: y, width: w, height: h)
        let rect: CGRect? = withWindow(windowID) { window, pid in
            withEnhancedUIDisabled(pid: pid) {
                applyFrame(window, target)
            }
        }
        return rect.map(FrameInfo.init)
    }

    /// 指定ウィンドウへフォーカスを移す（アプリの前面化 + キーウィンドウ確定 + 重なり順）。
    @discardableResult
    static func focus(windowID: CGWindowID) -> Bool {
        guard let pid = ownerPID(of: windowID) else { return false }

        // 1. WindowServer 経由でアプリ前面化 + キーウィンドウ確定（対象アプリを待たない）。
        var ok = PrivateAPI.focusWindow(pid: pid, windowID: windowID)
        if !ok {
            // private シンボルが失われた場合の保険。アプリ単位までしか指定できない。
            ok = AppAPI.activate(pid: pid)
        }

        // 2. 同一アプリ内の重なり順を整える（こちらは AX なので専用スレッドへ）。
        _ = withWindow(windowID) { window, _ in
            AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        }
        return ok
    }

    /// 指定ウィンドウの最小化状態を設定する。
    @discardableResult
    static func minimize(windowID: CGWindowID, _ minimized: Bool) -> Bool {
        withWindow(windowID) { window, _ in
            let value = (minimized ? kCFBooleanTrue : kCFBooleanFalse)!
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value) == .success
        } ?? false
    }

    /// 現在フォーカスされているウィンドウの CGWindowID を返す。
    ///
    /// システム全体の AX 要素への問い合わせは内部的に最前面アプリへ転送されるため、
    /// 相手がハングしていればブロックしうる。専用スレッド + タイムアウトで囲う。
    static func focusedWindowID() -> CGWindowID? {
        AXThreadPool.run(pid: AXThreadPool.systemWidePID) { () -> CGWindowID? in
            let system = AXUIElementCreateSystemWide()
            guard let app = element(system, kAXFocusedApplicationAttribute),
                  let window = element(app, kAXFocusedWindowAttribute) else { return nil }
            return PrivateAPI.windowID(of: window)
        } ?? nil
    }

    // MARK: - AX プリミティブ（すべて AX スレッド上で呼ばれる前提）

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copyElement(window, kAXPositionAttribute),
              let sizeValue = copyElement(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// 目標矩形を当てて、実際に落ち着いた矩形を返す。
    private static func applyFrame(_ window: AXUIElement, _ target: CGRect) -> CGRect {
        // 先に移動して目標ディスプレイ上へ置いてから寸法を決める。逆順だと
        // 「移動前のディスプレイの可視領域」でクランプされることがある。
        _ = setPosition(window, target.origin)
        _ = setSize(window, target.size)
        // リサイズで押し戻された分を当て直す。
        _ = setPosition(window, target.origin)

        var achieved = frame(of: window) ?? target
        // ずれていたら 1 回だけ再試行する。最小サイズ等の物理的な制約が理由なら
        // 2 回目も同じ結果になるので、それ以上は粘らない（呼び出し側が実測値を見る）。
        if !achieved.equalTo(target, tolerance: 1.0) {
            _ = setSize(window, target.size)
            _ = setPosition(window, target.origin)
            achieved = frame(of: window) ?? achieved
        }
        return achieved
    }

    /// 書き込みの間だけ `AXEnhancedUserInterface` を落とす。
    ///
    /// このアプリ属性が立っていると、多くのアプリ（Electron / Chromium / JetBrains 系など）が
    /// ウィンドウの位置・サイズ変更を**アニメーション付きで遅延適用**するようになり、
    /// 直後に読み返した値が要求と食い違う・タイルが目に見えてガタつく、といった症状になる。
    /// 元から立っていた場合のみ、書き込み後に必ず戻す（支援技術の動作を壊さないため）。
    private static func withEnhancedUIDisabled<T>(pid: pid_t, _ body: () -> T) -> T {
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface"
        let wasEnabled = (copyElement(app, key) as? Bool) == true
        if wasEnabled {
            AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanFalse!)
        }
        defer {
            if wasEnabled {
                AXUIElementSetAttributeValue(app, key as CFString, kCFBooleanTrue!)
            }
        }
        return body()
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// 属性値を `AXUIElement` として取り出す（型が違えば nil）。
    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyElement(owner, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func appWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let raw = copyElement(app, kAXWindowsAttribute),
              let windows = raw as? [AXUIElement] else { return [] }
        return windows
    }

    // MARK: - CGWindowID → AXUIElement の解決とキャッシュ

    private struct CachedWindow {
        let pid: pid_t
        let element: AXUIElement
    }

    private static let cacheLock = NSLock()
    private static var cache: [CGWindowID: CachedWindow] = [:]
    /// 際限なく増えないように上限を設ける（超えたら丸ごと捨てて引き直す）。
    private static let cacheLimit = 512

    /// `windowID` に対応する AX 要素を解決し、その pid の専用スレッド上で `body` を実行する。
    ///
    /// 解決（アプリのウィンドウ列挙 + `_AXUIElementGetWindow` 照合）も AX 呼び出しなので、
    /// `body` と**同じ 1 回の往復の中**で行う。解決できない・タイムアウトした場合は nil。
    private static func withWindow<T>(_ windowID: CGWindowID,
                                      timeout: TimeInterval = AXThreadPool.defaultTimeout,
                                      _ body: @escaping (AXUIElement, pid_t) -> T) -> T? {
        if let cached = cachedWindow(windowID),
           let value = attempt(windowID, pid: cached.pid, hint: cached.element, timeout: timeout, body) {
            return value
        }
        // キャッシュが無い / 古い。CGWindowList で pid を引き直して再解決する。
        dropCache(windowID)
        guard let pid = ownerPID(of: windowID) else { return nil }
        return attempt(windowID, pid: pid, hint: nil, timeout: timeout, body)
    }

    private static func attempt<T>(_ windowID: CGWindowID,
                                   pid: pid_t,
                                   hint: AXUIElement?,
                                   timeout: TimeInterval,
                                   _ body: @escaping (AXUIElement, pid_t) -> T) -> T? {
        let outcome: (AXUIElement, T)? = AXThreadPool.run(pid: pid, timeout: timeout) { () -> (AXUIElement, T)? in
            guard let window = locate(windowID: windowID, pid: pid, hint: hint) else { return nil }
            return (window, body(window, pid))
        } ?? nil
        guard let outcome else { return nil }
        store(windowID, CachedWindow(pid: pid, element: outcome.0))
        return outcome.1
    }

    /// AX スレッド上でウィンドウ要素を特定する。ヒントが今も同じウィンドウを指していれば
    /// 列挙を省ける（タイル敷き直しのような連続操作では毎回ここで当たる）。
    private static func locate(windowID: CGWindowID, pid: pid_t, hint: AXUIElement?) -> AXUIElement? {
        if let hint, PrivateAPI.windowID(of: hint) == windowID { return hint }
        return appWindows(pid: pid).first { PrivateAPI.windowID(of: $0) == windowID }
    }

    /// CGWindowID から所有プロセスの pid を引く（キャッシュ優先）。
    static func ownerPID(of windowID: CGWindowID) -> pid_t? {
        if let cached = cachedWindow(windowID) { return cached.pid }
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let raw = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]],
              let dict = raw.first,
              let pid = dict[kCGWindowOwnerPID as String] as? pid_t
        else { return nil }
        return pid
    }

    private static func cachedWindow(_ windowID: CGWindowID) -> CachedWindow? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[windowID]
    }

    private static func store(_ windowID: CGWindowID, _ entry: CachedWindow) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[windowID] = entry
    }

    private static func dropCache(_ windowID: CGWindowID) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeValue(forKey: windowID)
    }
}

private extension CGRect {
    /// 端数（HiDPI のピクセル丸め等）を無視した一致判定。
    func equalTo(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
            abs(origin.y - other.origin.y) <= tolerance &&
            abs(size.width - other.size.width) <= tolerance &&
            abs(size.height - other.size.height) <= tolerance
    }
}
#endif
