import Foundation
import WasmKit
import WasmKitWASI

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
///   - Ruby→Swift は専用 fd 上の同期 JSON-RPC（`RpcChannel`）。Ruby の write→read の
///     境界内で `RpcBridge.dispatch` を同期実行する。
final class RubyVM {

    /// Ruby→Swift RPC に使う専用 fd 番号（Ruby 側 `wm.rb` と一致させる）。
    static let rpcFD: Int32 = 3

    private let engine: Engine
    private let store: Store
    private var instance: Instance!
    private let channel = RpcChannel()

    init(wasmPath: String) throws {
        self.engine = Engine()
        self.store = Store(engine: engine)
        try instantiate(wasmPath: wasmPath)
    }

    // MARK: - インスタンス化

    private func instantiate(wasmPath: String) throws {
        let module = try parseWasm(filePath: FilePath(wasmPath))

        // WASI ブリッジ。args[0] はプログラム名。preopen でカレントを見せる。
        let wasi = try WASIBridgeToHost(
            args: ["ruby", "-e", ""],
            environment: [:],
            preopens: ["/": FilePath(NSHomeDirectory())]
        )

        var imports = Imports()
        wasi.link(to: &imports, store: store)

        // 専用 fd の fd_write / fd_read を RPC 用に差し替える（Part B-1）。
        // WASI が定義した同名 import を、fd を見て分岐するラッパで上書きする。
        installRpcHooks(into: &imports, wasi: wasi)

        self.instance = try module.instantiate(store: store, imports: imports)

        // ruby.wasm の初期化（wizer 済みビルドは _initialize、通常は _start）。
        if let initialize = instance.exports[function: "_initialize"] {
            _ = try initialize()
        } else {
            try wasi.start(instance, store: store)
        }
    }

    /// fd_write / fd_read をフックして、`rpcFD` への I/O を `RpcBridge` に橋渡しする。
    ///
    /// NOTE: 下記は WasmKit の Imports/Function/Caller API に合わせて実機で確定させる。
    /// 線形メモリの読み書き（iovec 走査）も WasmKit の Memory アクセサに合わせる。
    private func installRpcHooks(into imports: inout Imports, wasi: WASIBridgeToHost) {
        // 擬似コード水準の意図（実機で WasmKit の型に合わせて実装）:
        //
        //   imports.define("wasi_snapshot_preview1", "fd_write") { caller, args in
        //       let fd = args[0].i32
        //       if fd == UInt32(Self.rpcFD) {
        //           let bytes = readIOVecs(caller, iovsPtr: args[1], iovsLen: args[2])
        //           channel.appendRequest(bytes)           // 1 行分そろったら…
        //           let response = RpcBridge.dispatch(channel.takeRequest())
        //           channel.enqueueResponse(response)      // 次の fd_read 用に保持
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
    /// （キーディスパッチで consume 判定に使うため Bool を返す簡易版）
    @discardableResult
    func eval(_ code: String) throws -> Bool {
        // 実機実装の流れ:
        //   1. `code` を UTF-8 で wasm 線形メモリへ確保（ruby.wasm の `malloc` エクスポート使用）。
        //   2. `rb_eval_string_protect`(または rb_abi_guest 版) を invoke。
        //   3. 戻り VALUE の truthy 判定（Qnil/Qfalse 以外なら true）。state 非0 は例外。
        //   4. 確保したメモリを `free`。
        //
        // ここでは骨格として、評価結果を RpcChannel 経由で受け取れるようにしておく。
        try evaluateOnVM(code)
        return channel.lastEvalTruthy
    }

    private func evaluateOnVM(_ code: String) throws {
        // TODO(on-mac): instance.exports[function: "rb_eval_string_protect"] を呼ぶ。
        // 採用 ruby.wasm ビルドのエクスポート名・ABI に合わせて実装する。
        _ = code
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

/// Ruby→Swift RPC の同期チャネル。fd_write で積まれたリクエストを `RpcBridge` に流し、
/// 応答を fd_read 用にバッファする。単一スレッド・同期前提のためロック不要。
final class RpcChannel {
    private var requestBuffer = Data()
    private var responseBuffer = Data()
    private(set) var lastEvalTruthy = false

    /// fd_write された生バイトを受け取り、改行で 1 リクエストが揃ったら処理する。
    func appendRequest(_ bytes: Data) {
        requestBuffer.append(bytes)
        while let nl = requestBuffer.firstIndex(of: 0x0A) {
            let line = requestBuffer[requestBuffer.startIndex..<nl]
            requestBuffer.removeSubrange(requestBuffer.startIndex...nl)
            var response = RpcBridge.dispatch(Data(line))
            response.append(0x0A) // Ruby 側は行単位で read する
            responseBuffer.append(response)
        }
    }

    /// fd_read 要求に対して、バッファ済み応答から最大 `max` バイト払い出す。
    func dequeueResponse(max: Int) -> Data {
        let n = Swift.min(max, responseBuffer.count)
        let chunk = responseBuffer.prefix(n)
        responseBuffer.removeFirst(n)
        return Data(chunk)
    }
}
