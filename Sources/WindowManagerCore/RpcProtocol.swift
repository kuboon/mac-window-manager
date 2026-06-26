import Foundation

/// Ruby ⇄ Swift JSON-RPC の **ワイヤフォーマット**（プラットフォーム非依存）。
///
/// リクエスト: `{"method": "<name>", "args": [...]}`
/// レスポンス: `{"ok": true, "result": <any>}` または `{"ok": false, "error": "<msg>"}`
///
/// パース・整形・引数の型強制といった純ロジックをここに集約し、macOS 固有の
/// メソッド振り分け（`RpcBridge`）から分離する。これにより Linux で `swift test` できる。
public enum RpcProtocol {

    /// パース済みリクエスト。
    public struct Request {
        public let method: String
        public let args: [Any]
        public init(method: String, args: [Any]) {
            self.method = method
            self.args = args
        }
    }

    /// 生バイト列（1 行）を `Request` にパースする。不正なら `nil`。
    public static func parse(_ requestData: Data) -> Request? {
        guard let obj = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
              let method = obj["method"] as? String else {
            return nil
        }
        let args = obj["args"] as? [Any] ?? []
        return Request(method: method, args: args)
    }

    // MARK: - 引数の型強制（Ruby から来る数値は Int / Double / NSNumber が混在しうる）

    /// `i` 番目の引数を `Int` として取り出す（範囲外・非数値は 0）。
    public static func int(_ args: [Any], _ i: Int) -> Int {
        guard i < args.count else { return 0 }
        if let n = args[i] as? Int { return n }
        if let n = args[i] as? Double { return Int(n) }
        if let n = args[i] as? NSNumber { return n.intValue }
        return 0
    }

    /// `i` 番目の引数を `Double` として取り出す（範囲外・非数値は 0）。
    public static func double(_ args: [Any], _ i: Int) -> Double {
        guard i < args.count else { return 0 }
        if let n = args[i] as? Double { return n }
        if let n = args[i] as? Int { return Double(n) }
        if let n = args[i] as? NSNumber { return n.doubleValue }
        return 0
    }

    /// `i` 番目の引数を `Bool` として取り出す（範囲外は `fallback`）。
    public static func bool(_ args: [Any], _ i: Int, fallback: Bool = false) -> Bool {
        guard i < args.count else { return fallback }
        if let b = args[i] as? Bool { return b }
        if let n = args[i] as? NSNumber { return n.boolValue }
        return fallback
    }

    // MARK: - レスポンス整形

    /// `{"ok": true, "result": <result>}` を返す。`result` は JSON 化可能な値。
    public static func ok(_ result: Any) -> Data {
        serialize(["ok": true, "result": result])
    }

    /// `{"ok": false, "error": <message>}` を返す。
    public static func error(_ message: String) -> Data {
        serialize(["ok": false, "error": message])
    }

    /// `Encodable` を JSON オブジェクト（`[String: Any]` / `[Any]`）へ変換する。
    public static func encode<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// `[String: Any]` を JSON バイト列へ直列化する（失敗時は固定のエラー JSON）。
    public static func serialize(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object))
            ?? Data(#"{"ok":false,"error":"serialize failed"}"#.utf8)
    }
}
