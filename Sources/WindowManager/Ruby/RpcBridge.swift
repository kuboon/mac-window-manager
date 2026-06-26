#if canImport(AppKit)
import CoreGraphics
import Foundation
import WindowManagerCore

/// Ruby → Swift の同期 JSON-RPC の **メソッド振り分け**（Part B-1, macOS 固有）。
///
/// ワイヤフォーマットのパース・整形は `WindowManagerCore.RpcProtocol` に委譲し、
/// ここでは各メソッドを Part A の公開 API（`WindowAPI`/`ScreenAPI`/`AppAPI`）へ繋ぐ。
/// `dispatch` は `RpcChannel`（Core）から Ruby の write→read 境界の内側で同期呼び出しされる。
/// 全ネイティブ API はメインスレッドで実行される前提。
enum RpcBridge {

    /// 1 リクエスト（改行なしの 1 行）を処理して 1 レスポンスを返す。
    static func dispatch(_ requestData: Data) -> Data {
        guard let req = RpcProtocol.parse(requestData) else {
            return RpcProtocol.error("malformed request")
        }
        do {
            return try handle(method: req.method, args: req.args)
        } catch {
            return RpcProtocol.error("dispatch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - メソッド振り分け（Part A の「公開 API」表に対応）

    private static func handle(method: String, args: [Any]) throws -> Data {
        switch method {
        case "windows":
            return RpcProtocol.ok(try RpcProtocol.encode(WindowAPI.listWindows()))

        case "screens":
            return RpcProtocol.ok(try RpcProtocol.encode(ScreenAPI.listScreens()))

        case "apps":
            return RpcProtocol.ok(try RpcProtocol.encode(AppAPI.listApps()))

        case "focused_window":
            if let id = WindowAPI.focusedWindowID() {
                return RpcProtocol.ok(Double(id))
            }
            return RpcProtocol.ok(NSNull())

        case "move":
            let id = windowID(args, 0)
            return RpcProtocol.ok(WindowAPI.move(windowID: id,
                                                 x: RpcProtocol.double(args, 1),
                                                 y: RpcProtocol.double(args, 2)))

        case "resize":
            let id = windowID(args, 0)
            return RpcProtocol.ok(WindowAPI.resize(windowID: id,
                                                   w: RpcProtocol.double(args, 1),
                                                   h: RpcProtocol.double(args, 2)))

        case "raise":
            return RpcProtocol.ok(WindowAPI.raise(windowID: windowID(args, 0)))

        case "minimize":
            let id = windowID(args, 0)
            return RpcProtocol.ok(WindowAPI.minimize(windowID: id,
                                                     RpcProtocol.bool(args, 1, fallback: true)))

        case "activate":
            return RpcProtocol.ok(AppAPI.activate(pid: pid_t(RpcProtocol.int(args, 0))))

        case "hide_app":
            return RpcProtocol.ok(AppAPI.hide(pid: pid_t(RpcProtocol.int(args, 0))))

        default:
            return RpcProtocol.error("unknown method: \(method)")
        }
    }

    private static func windowID(_ args: [Any], _ i: Int) -> CGWindowID {
        CGWindowID(RpcProtocol.int(args, i))
    }
}
#endif
