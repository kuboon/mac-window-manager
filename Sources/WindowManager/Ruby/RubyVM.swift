#if canImport(AppKit)
import Foundation
import SystemPackage   // FilePath（parseWasm で使用）
import WasmKit
import WasmKitWASI
import WindowManagerCore

/// ruby.wasm を WasmKit 上で実行し、Ruby コードの評価と Ruby⇄Swift ブリッジを担うラッパ（Part B-2）。
///
/// ＝＝＝ 実装ステータス ＝＝＝
/// eval パイプライン（instantiate / 起動 / `rb-eval-string-protect` / 文字列の読み戻し /
/// 例外検出）は **Linux スパイク（`spike/ruby-wasm`）で実証済みの ABI** に基づく。
/// 詳細な根拠は `docs/ruby-wasm-spike.md` を参照。残る未実証ポイントは fd=3 の
/// RPC フック（`installRpcHooks`）のみ（次セッションの de-risk 課題）。
///
/// 採用ビルドは `@ruby/3.x-wasm-wasi`（reactor + WIT component `rb-abi-guest`）。
/// 生 C-API（`rb_eval_string_protect` / `malloc`）は export されておらず、
/// 代わりに **canonical ABI**（`cabi_realloc` での文字列受け渡し・間接 return）と
/// **24 関数のホストシム**（`canonical_abi` 3 + `rb-js-abi-host` 21、JS 不使用なので大半 stub）を要する。
///
/// ⚠️ ruby.wasm の import / export 名は WIT シグネチャ付きで装飾されている
///    （例: `rb-eval-string-protect: func(str: string) -> tuple<...>`）。
///    完全一致では引けないため、`module.exports` を接頭辞照合して実名で解決する。
final class RubyVM {

    /// RPC のバッキングに使う preopen のゲスト側パスとホスト側ディレクトリ。
    /// Ruby（`wm.rb`）はこの配下の `RPC_PATH` を `File.open(_, "w+")` で開く（本物の
    /// read-write fd を得るため。phantom fd は MRI が書込モードで開けない。§6）。
    static let rpcGuestDir = "/rpc"
    /// preopen dir=fd3 / stdio=0,1,2 を除いた最初の実 fd を RPC とみなす（§6-3）。
    static let rpcFDMin: UInt32 = 4

    /// 起動時に Ruby VM へ渡す引数（各要素 NUL 終端 / `list<string>` として lower）。
    /// `-e_=0` は stdin 待ちを避けるためのダミースクリプト。
    static let initArgs = ["ruby.wasm\u{0}", "-EUTF-8\u{0}", "-e_=0\u{0}"]

    private let engine: Engine
    private let store: Store
    private var instance: Instance!
    private var memory: Memory!

    /// guest 内に確保したリソースハンドル（`rb-abi-value`）の rep を保持する。
    private var reps: [UInt32: UInt32] = [:]
    private var handleCounter: UInt32 = 0

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

        // RPC のバッキング用に実ディレクトリを preopen する（§6）。stdlib は wasm 内蔵だが、
        // Ruby が本物の read-write fd を得るために実在の preopen が要る。
        let hostRpcDir = NSTemporaryDirectory() + "wmrc-rpc-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: hostRpcDir,
                                                 withIntermediateDirectories: true)
        let wasi = try WASIBridgeToHost(args: ["ruby"], environment: [:],
                                        preopens: [Self.rpcGuestDir: hostRpcDir])

        var imports = Imports()
        wasi.link(to: &imports, store: store)

        // ruby.wasm が要求する非 WASI import（canonical_abi / rb-js-abi-host）を充足する。
        defineHostShim(from: module, into: &imports)

        // fd_write / fd_read を上書きし、RPC fd を RpcChannel に橋渡しする（Part B-1）。
        installRpcHooks(into: &imports)

        self.instance = try module.instantiate(store: store, imports: imports)
        guard let mem = instance.exports[memory: "memory"] else {
            throw RubyVMError("ruby.wasm に memory export が無い")
        }
        self.memory = mem

        // 起動: _initialize → ruby-init（NUL 終端引数）。ruby-init-loadpath は単独で呼ばない。
        if let initialize = exportFunction("_initialize") { _ = try initialize([]) }
        if let rubyInit = exportFunction("ruby-init:") {
            let listPtr = try lowerStringList(Self.initArgs)
            _ = try rubyInit([.i32(listPtr.ptr), .i32(listPtr.count)])
        }
    }

    /// `canonical_abi` / `rb-js-abi-host` の import を、モジュール宣言の実名・実型から自動生成する。
    /// 大半は JS 相互運用フックで、窓マネージャでは呼ばれないため stub（型に合う 0 を返す）。
    private func defineHostShim(from module: Module, into imports: inout Imports) {
        for imp in module.imports where imp.module == "canonical_abi" || imp.module == "rb-js-abi-host" {
            guard case .function(let ti) = imp.descriptor else { continue }
            let ft = module.types[Int(ti)]
            let mod = imp.module, name = imp.name
            let fn: (Caller, [Value]) throws -> [Value]
            if name.hasPrefix("resource_new_rb-abi-value") {
                fn = { [self] _, args in
                    handleCounter += 1; reps[handleCounter] = args[0].i32; return [.i32(handleCounter)]
                }
            } else if name.hasPrefix("resource_get_rb-abi-value") {
                fn = { [self] _, args in [.i32(reps[args[0].i32] ?? 0)] }
            } else {
                fn = { _, _ in ft.results.map { t in
                    switch t { case .i64: return .i64(0); case .f32: return .f32(0)
                               case .f64: return .f64(0); default: return .i32(0) }
                } }
            }
            imports.define(module: mod, name: name,
                           Function(store: store, type: ft, body: fn))
        }
    }

    /// fd_write / fd_read を上書きし、RPC fd への I/O を `channel` へ橋渡しする（Part B-1）。
    ///
    /// `spike/ruby-wasm`（rbrpc）で実証した方式（`docs/ruby-wasm-spike.md` §6）:
    ///   - fd 1/2 はホスト stdout/stderr へ自前で流す（WASI への委譲は不要）。
    ///   - fd ≥ `rpcFDMin`（= Ruby が開く実 RPC fd）は RpcChannel へ橋渡しし同期ディスパッチ。
    ///   - iovec 走査は `caller.instance.exports[memory:]` 経由で `Memory.withUnsafeMutableBufferPointer`。
    /// fd_fdstat_get / path_open など他の fd 操作は本物の WASI に委譲（上書きしない）。
    private func installRpcHooks(into imports: inout Imports) {
        let channel = self.channel
        let rpcMin = Self.rpcFDMin

        imports.define(module: "wasi_snapshot_preview1", name: "fd_write",
                       Function(store: store, parameters: [.i32, .i32, .i32, .i32], results: [.i32]) { caller, args in
            guard let mem = caller.instance?.exports[memory: "memory"] else { return [.i32(8)] }
            let fd = args[0].i32, iovs = args[1].i32, n = args[2].i32, nwrittenPtr = args[3].i32
            var data = Data()
            for i in 0..<n {
                let base = iovs + i * 8
                let ptr = Self.loadU32(mem, base), len = Self.loadU32(mem, base + 4)
                data.append(Self.loadBytes(mem, ptr, len))
            }
            switch fd {
            case 1: FileHandle.standardOutput.write(data)
            case 2: FileHandle.standardError.write(data)
            case let f where f >= rpcMin: channel.appendRequest(data)
            default: return [.i32(8)] // EBADF
            }
            Self.storeU32(mem, nwrittenPtr, UInt32(data.count))
            return [.i32(0)]
        })

        imports.define(module: "wasi_snapshot_preview1", name: "fd_read",
                       Function(store: store, parameters: [.i32, .i32, .i32, .i32], results: [.i32]) { caller, args in
            guard let mem = caller.instance?.exports[memory: "memory"] else { return [.i32(8)] }
            let fd = args[0].i32, iovs = args[1].i32, n = args[2].i32, nreadPtr = args[3].i32
            guard fd >= rpcMin else {
                if fd == 0 { Self.storeU32(mem, nreadPtr, 0); return [.i32(0)] } // stdin EOF
                return [.i32(8)]
            }
            var total: UInt32 = 0
            for i in 0..<n {
                let base = iovs + i * 8
                let buf = Self.loadU32(mem, base), len = Self.loadU32(mem, base + 4)
                let chunk = channel.dequeueResponse(max: Int(len))
                if chunk.isEmpty { break }
                Self.storeBytes(mem, buf, chunk)
                total += UInt32(chunk.count)
                if chunk.count < Int(len) { break }
            }
            Self.storeU32(mem, nreadPtr, total)
            return [.i32(0)]
        })
    }

    // MARK: - Caller 内で使う Memory ヘルパ（static: フック内で self を捕捉しないため）

    private static func loadU32(_ m: Memory, _ p: UInt32) -> UInt32 {
        var v: UInt32 = 0
        m.withUnsafeMutableBufferPointer(offset: UInt(p), count: 4) { b in
            for i in 0..<4 { v |= UInt32(b[i]) << (8 * i) }
        }
        return v
    }
    private static func storeU32(_ m: Memory, _ p: UInt32, _ v: UInt32) {
        m.withUnsafeMutableBufferPointer(offset: UInt(p), count: 4) { b in
            for i in 0..<4 { b[i] = UInt8((v >> (8 * i)) & 0xff) }
        }
    }
    private static func loadBytes(_ m: Memory, _ p: UInt32, _ n: UInt32) -> Data {
        guard n > 0 else { return Data() }
        var out = Data(count: Int(n))
        m.withUnsafeMutableBufferPointer(offset: UInt(p), count: Int(n)) { b in
            for i in 0..<Int(n) { out[i] = b[i] }
        }
        return out
    }
    private static func storeBytes(_ m: Memory, _ p: UInt32, _ bytes: Data) {
        guard !bytes.isEmpty else { return }
        m.withUnsafeMutableBufferPointer(offset: UInt(p), count: bytes.count) { b in
            for (i, byte) in bytes.enumerated() { b[i] = byte }
        }
    }

    // MARK: - 線形メモリ / canonical ABI ヘルパ

    private func exportFunction(_ prefix: String) -> Function? {
        for exp in instance.exports where exp.name.hasPrefix(prefix) {
            if case .function(let f) = exp.value { return f }
        }
        return nil
    }

    private func writeBytes(_ ptr: UInt32, _ bytes: [UInt8]) {
        memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: bytes.count) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
    }

    private func readU32(_ ptr: UInt32) -> UInt32 {
        var v: UInt32 = 0
        memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: 4) { buf in
            for i in 0..<4 { v |= UInt32(buf[i]) << (8 * i) }
        }
        return v
    }

    private func writeU32(_ ptr: UInt32, _ val: UInt32) {
        writeBytes(ptr, (0..<4).map { UInt8((val >> (8 * $0)) & 0xff) })
    }

    /// `cabi_realloc(0, 0, align, size)` で guest メモリを確保する。
    private func alloc(_ size: Int, align: Int) throws -> UInt32 {
        guard let realloc = exportFunction("cabi_realloc") else {
            throw RubyVMError("cabi_realloc export が無い")
        }
        let r = try realloc([.i32(0), .i32(0), .i32(UInt32(align)), .i32(UInt32(size))])
        return r[0].i32
    }

    /// String を guest メモリへ書き、(ptr, len) を返す。
    private func lowerString(_ s: String) throws -> (ptr: UInt32, count: UInt32) {
        let bytes = Array(s.utf8)
        let p = try alloc(bytes.count, align: 1)
        writeBytes(p, bytes)
        return (p, UInt32(bytes.count))
    }

    /// `list<string>` を lower し、リスト先頭 ptr と要素数を返す。
    private func lowerStringList(_ items: [String]) throws -> (ptr: UInt32, count: UInt32) {
        let descs = try items.map { try lowerString($0) }
        let listPtr = try alloc(descs.count * 8, align: 4)
        for (i, d) in descs.enumerated() {
            writeU32(listPtr + UInt32(i * 8), d.ptr)
            writeU32(listPtr + UInt32(i * 8 + 4), d.count)
        }
        return (listPtr, UInt32(descs.count))
    }

    /// `rstring-ptr` で Ruby String のハンドルを Swift String に取り出す（+ `cabi_post` 解放）。
    private func liftRubyString(_ handle: UInt32) throws -> String {
        guard let rstringPtr = exportFunction("rstring-ptr") else {
            throw RubyVMError("rstring-ptr export が無い")
        }
        let r = try rstringPtr([.i32(handle)])
        let area = r[0].i32
        let ptr = readU32(area), len = readU32(area + 4)
        var bytes = [UInt8](repeating: 0, count: Int(len))
        memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: Int(len)) { buf in
            for i in 0..<Int(len) { bytes[i] = buf[i] }
        }
        if case .function(let post)? = instance.exports["cabi_post_rstring-ptr"] {
            _ = try post([.i32(area)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - 評価

    /// 任意の Ruby コードを評価する。戻り値は Ruby の結果が truthy かどうか。
    @discardableResult
    func eval(_ code: String) throws -> Bool {
        // truthy 判定は不透明なハンドルからは取れないため、Ruby 側で "1"/"0" に畳んで読み戻す。
        let wrapped = "((\(code)) ? \"1\" : \"0\")"
        let (handle, state) = try evaluateOnVM(wrapped)
        if state != 0 {
            let message = (try? errorMessage()) ?? "Ruby exception (state=\(state))"
            clearError()
            throw RubyVMError(message)
        }
        lastEvalTruthy = ((try? liftRubyString(handle)) == "1")
        return lastEvalTruthy
    }

    /// `rb-eval-string-protect` を呼び、(結果ハンドル, state) を返す。state 非0 は例外。
    private func evaluateOnVM(_ code: String) throws -> (handle: UInt32, state: UInt32) {
        guard let evalFn = exportFunction("rb-eval-string-protect") else {
            throw RubyVMError("rb-eval-string-protect export が無い")
        }
        let s = try lowerString(code)
        let r = try evalFn([.i32(s.ptr), .i32(s.count)])
        let retptr = r[0].i32
        return (readU32(retptr), readU32(retptr + 4))
    }

    /// 直近の Ruby 例外メッセージ（`rb-errinfo` の `.to_s`）。
    private func errorMessage() throws -> String? {
        guard let errinfo = exportFunction("rb-errinfo") else { return nil }
        let r = try errinfo([])
        return try? liftRubyString(r[0].i32)
    }

    private func clearError() {
        if let clear = exportFunction("rb-clear-errinfo") { _ = try? clear([]) }
    }

    /// 起動時に同梱の Ruby ライブラリ（wm.rb）とユーザ設定（~/.wmrc.rb）を読み込む。
    func bootstrap(wmLib: String, userConfigPath: String) throws {
        try evalRaw(wmLib)
        if let config = try? String(contentsOfFile: userConfigPath, encoding: .utf8) {
            try evalRaw(config)
        }
    }

    /// truthy 判定を伴わない素の eval（ライブラリ読み込み等、結果値が不要なとき）。
    @discardableResult
    private func evalRaw(_ code: String) throws -> UInt32 {
        let (handle, state) = try evaluateOnVM(code)
        if state != 0 {
            let message = (try? errorMessage()) ?? "Ruby exception (state=\(state))"
            clearError()
            throw RubyVMError(message)
        }
        return handle
    }

    /// キーイベントを Ruby 側ハンドラへディスパッチし、consume するかを返す（Part B-3）。
    func dispatchKey(_ event: KeyEvent) -> Bool {
        let expr = "WM._dispatch_key(\(event.keyCode), \(event.flags), \(event.isKeyDown))"
        return (try? eval(expr)) ?? false
    }
}

struct RubyVMError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
#endif
