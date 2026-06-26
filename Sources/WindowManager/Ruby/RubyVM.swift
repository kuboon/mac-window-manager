#if canImport(AppKit)
import Foundation
import SystemPackage   // FilePath（parseWasm / WASIBridgeToHost の preopens で使用）
import WasmKit
import WasmKitWASI
import WindowManagerCore

/// ruby.wasm を WasmKit 上で実行し、Ruby コードの評価と Ruby⇄Swift ブリッジを担うラッパ（Part B-2）。
///
/// ＝＝＝ 実装ステータス（重要）＝＝＝
/// 本ファイルは「縦切り」の骨格であり、2 つの統合ポイントは **macOS 実機での確認が必要**:
///   (1) WasmKit の正確な API シグネチャ（Engine/Store/Module/Imports/Function/Caller の
///       現行版での綴り）。`Package.resolved` でピン留めしたバージョンに合わせて調整する。
///   (2) ruby.wasm の評価エントリポイント。`@ruby/wasm-wasi`(JS) の `RubyVM` 実装が用いる
///       `rb-abi-guest` コンポーネントのエクスポート（`rb_abi_guest_rb_eval_string_protect` 等）、
///       または raw C-API ビルドの `rb_eval_string_protect` を、採用する ruby.wasm ビルドに合わせる。
///
/// 設計上の流れ:
///   - 起動時に WASI で `_initialize`/`_start` を実行し Ruby VM を立ち上げる。
///   - `eval(_:)` で任意の Ruby を評価（ユーザの `~/.wmrc.rb`、キーディスパッチ式など）。
///   - Ruby→Swift は専用 fd 上の同期 JSON-RPC（`WindowManagerCore.RpcChannel`）。Ruby の
///     write→read の境界内で `RpcBridge.dispatch` を同期実行する。
final class RubyVM {

    /// Ruby→Swift RPC に使う専用 fd 番号（Ruby 側 `wm.rb` と一致させる）。
    static let rpcFD: Int32 = 3

    private let engine: Engine
    private let store: Store
    private var instance: Instance!

    /// RPC フレーミングはコア層に委譲し、ディスパッチ先だけ macOS 実装を注入する。
    private let channel = RpcChannel(dispatcher: RpcBridge.dispatch)

    /// 直近の `eval` 結果が truthy だったか（キーディスパッチの consume 判定に使用）。
    private(set) var lastEvalTruthy = false

    init(wasmPath: String) throws {
        self.engine = Engine()
        self.store = Store(engine: engine)
        try instantiate(wasmPath: wasmPath)
    }

    // MARK: - インスタンス化

    private func instantiate(wasmPath: String) throws {
        let module = try parseWasm(filePath: FilePath(wasmPath))

        // WASI ブリッジ。args[0] はプログラム名。preopen でホームを見せる。
        let wasi = try WASIBridgeToHost(
            args: ["ruby", "-e", ""],
            environment: [:],
            preopens: ["/": NSHomeDirectory()]   // guest path : host path（String）
        )

        var imports = Imports()
        wasi.link(to: &imports, store: store)

        // 専用 fd の fd_write / fd_read を RPC 用に差し替える（Part B-1）。
        installRpcHooks(into: &imports, wasi: wasi)

        self.instance = try module.instantiate(store: store, imports: imports)

        // ruby.wasm の初期化（wizer 済みビルドは _initialize、通常は _start）。
        if let initialize = instance.exports[function: "_initialize"] {
            _ = try initialize()
        } else {
            _ = try wasi.start(instance)
        }
    }

    /// fd_write / fd_read をフックして、`rpcFD` への I/O を `channel`（→ `RpcBridge`）へ橋渡しする。
    ///
    /// NOTE: 下記は WasmKit の Imports/Function/Caller API に合わせて実機で確定させる。
    /// 線形メモリの読み書き（iovec 走査）も WasmKit の Memory アクセサに合わせる。
    /// フレーミング自体はコア層（`channel.appendRequest` / `channel.dequeueResponse`）が担う。
    private func installRpcHooks(into imports: inout Imports, wasi: WASIBridgeToHost) {
        // 擬似コード水準の意図（実機で WasmKit の型に合わせて実装）:
        //
        //   imports.define("wasi_snapshot_preview1", "fd_write") { caller, args in
        //       let fd = args[0].i32
        //       if fd == UInt32(Self.rpcFD) {
        //           let bytes = readIOVecs(caller, iovsPtr: args[1], iovsLen: args[2])
        //           channel.appendRequest(bytes)           // 1 行そろえば同期ディスパッチ
        //           writeBack(caller, nwrittenPtr: args[3], n: bytes.count)
        //           return [.i32(0)]                       // errno 0
        //       }
        //       return wasiFdWrite(caller, args)           // それ以外は WASI 既定へ委譲
        //   }
        //
        //   imports.define("wasi_snapshot_preview1", "fd_read") { caller, args in
        //       let fd = args[0].i32
        //       if fd == UInt32(Self.rpcFD) {
        //           let chunk = channel.dequeueResponse(max: …)
        //           writeIOVecs(caller, iovsPtr: args[1], iovsLen: args[2], data: chunk)
        //           writeBack(caller, nreadPtr: args[3], n: chunk.count)
        //           return [.i32(0)]
        //       }
        //       return wasiFdRead(caller, args)
        //   }
        _ = wasi
        _ = imports
    }

    // MARK: - 評価

    /// 任意の Ruby コードを評価する。戻り値は Ruby の結果が truthy かどうか。
    @discardableResult
    func eval(_ code: String) throws -> Bool {
        // 実機実装の流れ:
        //   1. `code` を UTF-8 で wasm 線形メモリへ確保（ruby.wasm の `malloc` エクスポート使用）。
        //   2. `rb_eval_string_protect`(または rb_abi_guest 版) を invoke。
        //   3. 戻り VALUE の truthy 判定（Qnil/Qfalse 以外なら true）。state 非0 は例外。
        //   4. 確保したメモリを `free`。
        try evaluateOnVM(code)
        return lastEvalTruthy
    }

    private func evaluateOnVM(_ code: String) throws {
        // TODO(on-mac): instance.exports[function: "rb_eval_string_protect"] を呼ぶ。
        // 採用 ruby.wasm ビルドのエクスポート名・ABI に合わせて実装する。
        _ = code
        lastEvalTruthy = false
    }

    /// 起動時に同梱の Ruby ライブラリ（wm.rb）とユーザ設定（~/.wmrc.rb）を読み込む。
    func bootstrap(wmLib: String, userConfigPath: String) throws {
        try eval(wmLib)
        if let config = try? String(contentsOfFile: userConfigPath, encoding: .utf8) {
            try eval(config)
        }
    }

    /// キーイベントを Ruby 側ハンドラへディスパッチし、consume するかを返す（Part B-3）。
    func dispatchKey(_ event: KeyEvent) -> Bool {
        let expr = "WM._dispatch_key(\(event.keyCode), \(event.flags), \(event.isKeyDown))"
        return (try? eval(expr)) ?? false
    }
}
#endif
