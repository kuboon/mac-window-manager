#if canImport(AppKit)
import Foundation

/// `~/.wmrc.rb` から使う永続 KV ストア（JSON 1 ファイル）。
///
/// WASI 上の Ruby は `/rpc` 以外のファイルへ書けないため、永続化はホスト側で行う。
/// `store_set` / `store_get`（`RpcBridge`）の実体。値は JSON 化可能な任意の構造
/// （Ruby 側の `WM.save(key, value)` / `WM.load(key)`）。アプリはサンドボックス無効前提。
enum Store {

    /// 保存先: ~/Library/Application Support/WindowManager/state.json
    private static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WindowManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }()

    /// メモリキャッシュ（単一スレッド・同期前提）。
    private static var cache: [String: Any]?

    private static func load() -> [String: Any] {
        if let cached = cache { return cached }
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        cache = obj
        return obj
    }

    /// `key` に対応する値（無ければ nil）。
    static func get(_ key: String) -> Any? {
        let value = load()[key]
        return value is NSNull ? nil : value
    }

    /// `key` に値を保存し、ファイルへ書き出す。
    static func set(_ key: String, _ value: Any) {
        var dict = load()
        if value is NSNull {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = value
        }
        cache = dict
        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
#endif
