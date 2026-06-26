import CoreGraphics
import Foundation

/// Ruby → Swift の同期 JSON-RPC ディスパッチャ（Part B-1）。
///
/// リクエスト: `{"method": "<name>", "args": [...]}`
/// レスポンス: `{"ok": true, "result": <any>}` または `{"ok": false, "error": "<msg>"}`
///
/// `dispatch` は WASI レイヤ（`RubyVM` の fd ハンドラ）から、Ruby の `write`→`read`
/// 境界の内側で同期的に呼ばれる。全ネイティブ API はメインスレッドで実行される前提。
enum RpcBridge {

    /// 1 リクエストを処理して 1 レスポンスを返す。
    static func dispatch(_ requestData: Data) -> Data {
        do {
            guard let req = try JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let method = req["method"] as? String else {
                return error("malformed request")
            }
            let args = req["args"] as? [Any] ?? []
            return try handle(method: method, args: args)
        } catch {
            return self.error("dispatch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - メソッド振り分け（Part A の「公開 API」表に対応）

    private static func handle(method: String, args: [Any]) throws -> Data {
        switch method {
        case "windows":
            return try ok(encode(WindowAPI.listWindows()))

        case "screens":
            return try ok(encode(ScreenAPI.listScreens()))

        case "apps":
            return try ok(encode(AppAPI.listApps()))

        case "focused_window":
            if let id = WindowAPI.focusedWindowID() {
                return ok(.number(Double(id)))
            }
            return ok(.null)

        case "move":
            let (id, x, y) = (windowID(args, 0), double(args, 1), double(args, 2))
            return ok(.bool(WindowAPI.move(windowID: id, x: x, y: y)))

        case "resize":
            let (id, w, h) = (windowID(args, 0), double(args, 1), double(args, 2))
            return ok(.bool(WindowAPI.resize(windowID: id, w: w, h: h)))

        case "raise":
            return ok(.bool(WindowAPI.raise(windowID: windowID(args, 0))))

        case "minimize":
            let id = windowID(args, 0)
            let flag = (args.count > 1 ? (args[1] as? Bool ?? true) : true)
            return ok(.bool(WindowAPI.minimize(windowID: id, flag)))

        case "activate":
            return ok(.bool(AppAPI.activate(pid: pid_t(int(args, 0)))))

        case "hide_app":
            return ok(.bool(AppAPI.hide(pid: pid_t(int(args, 0)))))

        default:
            return error("unknown method: \(method)")
        }
    }

    // MARK: - 引数取り出しヘルパ

    private static func windowID(_ args: [Any], _ i: Int) -> CGWindowID {
        CGWindowID(int(args, i))
    }
    private static func int(_ args: [Any], _ i: Int) -> Int {
        guard i < args.count else { return 0 }
        if let n = args[i] as? Int { return n }
        if let n = args[i] as? Double { return Int(n) }
        if let n = args[i] as? NSNumber { return n.intValue }
        return 0
    }
    private static func double(_ args: [Any], _ i: Int) -> Double {
        guard i < args.count else { return 0 }
        if let n = args[i] as? Double { return n }
        if let n = args[i] as? Int { return Double(n) }
        if let n = args[i] as? NSNumber { return n.doubleValue }
        return 0
    }

    // MARK: - レスポンス整形

    /// JSON にそのまま入れられる軽量な値表現。
    private enum JSONValue {
        case bool(Bool), number(Double), null, raw(Any)
        var any: Any {
            switch self {
            case .bool(let b): return b
            case .number(let n): return n
            case .null: return NSNull()
            case .raw(let v): return v
            }
        }
    }

    private static func ok(_ value: JSONValue) -> Data {
        serialize(["ok": true, "result": value.any])
    }
    private static func ok(_ encodedResult: Any) -> Data {
        serialize(["ok": true, "result": encodedResult])
    }
    private static func error(_ message: String) -> Data {
        serialize(["ok": false, "error": message])
    }

    /// Codable を JSON オブジェクト（[String:Any]/[Any]）へ変換する。
    private static func encode<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"ok\":false,\"error\":\"serialize failed\"}".utf8)
    }
}
