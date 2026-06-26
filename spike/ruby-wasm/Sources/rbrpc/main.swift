import Foundation
import SystemPackage
import WasmKit
import WasmKitWASI

// fd ベース RPC ラウンドトリップの de-risk（改訂版）。
//
// 前バージョンの発見: phantom fd（ホスト側で fd_write/fd_read だけフックした fd）は
// MRI が書き込みモードで開けない（IO.new(3,"w"/"r+") が Errno::EINVAL）。
// wasi-libc が当該 fd を read-only とみなし、MRI の mode 整合チェックで弾かれるため。
//
// 改訂方針: **実在の preopen ディレクトリ配下のファイルを Ruby に開かせて
// 本物の read-write fd を取得**（MRI はこれを受理する）。その fd の fd_write/fd_read
// だけをフックして RPC チャネルへ橋渡しする（実ファイルには読み書きしない）。

let path = CommandLine.arguments[1]
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let engine = Engine()
let store = Store(engine: engine)
let module = try parseWasm(filePath: FilePath(path))

// ---- RPC チャネル（行単位フレーミング）----
final class Channel {
    private var req = [UInt8]()
    private var resp = [UInt8]()
    let dispatch: ([UInt8]) -> [UInt8]
    init(_ dispatch: @escaping ([UInt8]) -> [UInt8]) { self.dispatch = dispatch }
    func appendRequest(_ bytes: [UInt8]) {
        req.append(contentsOf: bytes)
        while let nl = req.firstIndex(of: 0x0A) {
            let line = Array(req[req.startIndex..<nl]); req.removeSubrange(req.startIndex...nl)
            if line.isEmpty { continue }
            resp.append(contentsOf: dispatch(line)); resp.append(0x0A)
        }
    }
    func dequeueResponse(max n: Int) -> [UInt8] {
        let k = Swift.min(n, resp.count); let chunk = Array(resp.prefix(k))
        resp.removeFirst(k); return chunk
    }
}
let channel = Channel { line in
    let s = String(decoding: line, as: UTF8.self)
    err("  [host] RPC request: \(s)")
    var args = "[]"
    if let d = s.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
       let a = obj["args"], let ad = try? JSONSerialization.data(withJSONObject: a) {
        args = String(decoding: ad, as: UTF8.self)
    }
    let reply = "{\"ok\":true,\"result\":\(args)}"
    err("  [host] RPC reply  : \(reply)")
    return Array(reply.utf8)
}

// ---- 実在の preopen ディレクトリ（RPC fd のバッキング）----
let rpcDir = NSTemporaryDirectory() + "rbrpc-\(getpid())"
try? FileManager.default.createDirectory(atPath: rpcDir, withIntermediateDirectories: true)

let wasi = try WASIBridgeToHost(args: ["ruby"], environment: [:], preopens: ["/rpc": rpcDir])
var imports = Imports()
wasi.link(to: &imports, store: store)

// ---- ホストシム（canonical_abi / rb-js-abi-host）----
var reps: [UInt32: UInt32] = [:]; var handleCounter: UInt32 = 0
func def(_ mod: String, _ name: String, _ p: [ValueType], _ r: [ValueType],
         _ body: @escaping (Caller, [Value]) throws -> [Value]) {
    imports.define(module: mod, name: name, Function(store: store, parameters: p, results: r, body: body))
}
for imp in module.imports where imp.module == "canonical_abi" || imp.module == "rb-js-abi-host" {
    guard case .function(let ti) = imp.descriptor else { continue }
    let ft = module.types[Int(ti)]; let name = imp.name
    if name.hasPrefix("resource_new_rb-abi-value") {
        def(imp.module, name, ft.parameters, ft.results) { _, a in
            handleCounter += 1; reps[handleCounter] = a[0].i32; return [.i32(handleCounter)] }
    } else if name.hasPrefix("resource_get_rb-abi-value") {
        def(imp.module, name, ft.parameters, ft.results) { _, a in [.i32(reps[a[0].i32] ?? 0)] }
    } else {
        def(imp.module, name, ft.parameters, ft.results) { _, _ in ft.results.map { t in
            switch t { case .i64: return .i64(0); case .f32: return .f32(0)
                       case .f64: return .f64(0); default: return .i32(0) } } }
    }
}

// ---- メモリヘルパ ----
func mem(_ caller: Caller) -> Memory { caller.instance!.exports[memory: "memory"]! }
func readU32(_ m: Memory, _ p: UInt32) -> UInt32 {
    var v: UInt32 = 0
    m.withUnsafeMutableBufferPointer(offset: UInt(p), count: 4) { b in for i in 0..<4 { v |= UInt32(b[i]) << (8*i) } }
    return v
}
func writeU32(_ m: Memory, _ p: UInt32, _ v: UInt32) {
    m.withUnsafeMutableBufferPointer(offset: UInt(p), count: 4) { b in for i in 0..<4 { b[i] = UInt8((v >> (8*i)) & 0xff) } }
}
func readBytes(_ m: Memory, _ p: UInt32, _ n: UInt32) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: Int(n))
    if n > 0 { m.withUnsafeMutableBufferPointer(offset: UInt(p), count: Int(n)) { b in for i in 0..<Int(n) { out[i] = b[i] } } }
    return out
}
func writeBytes(_ m: Memory, _ p: UInt32, _ bytes: ArraySlice<UInt8>) {
    if bytes.isEmpty { return }
    m.withUnsafeMutableBufferPointer(offset: UInt(p), count: bytes.count) { b in
        for (i, byte) in bytes.enumerated() { b[i] = byte } }
}

// ---- fd フック: fd_write / fd_read のみ上書き ----
// preopen dir は fd 3。Ruby が開く RPC ファイルは fd>=4（書き込み可能な実 fd）。
// その fd の I/O だけ RPC チャネルへ流す。fd_fdstat_get 等は本物の WASI に委譲（上書きしない）。
let RPC_FD_MIN: UInt32 = 4
def("wasi_snapshot_preview1", "fd_write", [.i32,.i32,.i32,.i32], [.i32]) { caller, a in
    let m = mem(caller)
    let fd = a[0].i32, iovs = a[1].i32, n = a[2].i32, nwp = a[3].i32
    var data = [UInt8]()
    for i in 0..<n { let base = iovs + i*8; data.append(contentsOf: readBytes(m, readU32(m, base), readU32(m, base+4))) }
    switch fd {
    case 1: FileHandle.standardOutput.write(Data(data))
    case 2: FileHandle.standardError.write(Data(data))
    case let f where f >= RPC_FD_MIN: channel.appendRequest(data)
    default: return [.i32(8)] // EBADF（preopen dir fd 3 へ書くことは無い想定）
    }
    writeU32(m, nwp, UInt32(data.count)); return [.i32(0)]
}
def("wasi_snapshot_preview1", "fd_read", [.i32,.i32,.i32,.i32], [.i32]) { caller, a in
    let m = mem(caller)
    let fd = a[0].i32, iovs = a[1].i32, n = a[2].i32, nrp = a[3].i32
    guard fd >= RPC_FD_MIN else { if fd == 0 { writeU32(m, nrp, 0); return [.i32(0)] }; return [.i32(8)] }
    var total: UInt32 = 0
    for i in 0..<n {
        let base = iovs + i*8; let buf = readU32(m, base), len = readU32(m, base+4)
        let chunk = channel.dequeueResponse(max: Int(len)); if chunk.isEmpty { break }
        writeBytes(m, buf, chunk[...]); total += UInt32(chunk.count)
        if chunk.count < Int(len) { break }
    }
    writeU32(m, nrp, total); return [.i32(0)]
}

// ---- instantiate + init ----
let instance = try module.instantiate(store: store, imports: imports)
func exportFn(_ prefix: String) -> Function? {
    for e in instance.exports where e.name.hasPrefix(prefix) { if case .function(let f) = e.value { return f } }
    return nil
}
let memory = instance.exports[memory: "memory"]!
func writeOut(_ p: UInt32, _ bytes: [UInt8]) { writeBytes(memory, p, bytes[...]) }
guard let realloc = exportFn("cabi_realloc") else { fatalError("no cabi_realloc") }
func alloc(_ size: Int, _ align: Int) throws -> UInt32 { try realloc([.i32(0),.i32(0),.i32(UInt32(align)),.i32(UInt32(size))])[0].i32 }
func lowerString(_ s: String) throws -> (UInt32, UInt32) { let b = Array(s.utf8); let p = try alloc(b.count, 1); writeOut(p, b); return (p, UInt32(b.count)) }

if let initialize = exportFn("_initialize") { _ = try initialize([]) }
if let rubyInit = exportFn("ruby-init:") {
    let argv = ["ruby.wasm\u{0}", "-EUTF-8\u{0}", "-e_=0\u{0}"]
    var descs = [(UInt32,UInt32)](); for s in argv { descs.append(try lowerString(s)) }
    let lp = try alloc(descs.count*8, 4)
    for (i,d) in descs.enumerated() { writeU32(memory, lp+UInt32(i*8), d.0); writeU32(memory, lp+UInt32(i*8+4), d.1) }
    _ = try rubyInit([.i32(lp), .i32(UInt32(descs.count))])
}
err("VM up; running RPC roundtrip ...")

// ---- Ruby 側 wm.rb 相当 ----
guard let evalFn = exportFn("rb-eval-string-protect") else { fatalError("no eval") }
func rbEval(_ code: String) throws { let (p, l) = try lowerString(code); let r = try evalFn([.i32(p), .i32(l)])
    if readU32(memory, r[0].i32 + 4) != 0 { err("Ruby exception state!=0") } }
let rubyCode = #"""
$stdout.sync = true
$stderr.sync = true
begin
require "json"
io = File.open("/rpc/sock", "w+")   # 実在 preopen 配下 → 本物の read-write fd
$stderr.puts "opened RPC io -> #{io.inspect} fileno=#{io.fileno}"
def rpc_call(io, method, *args)
  io.write(JSON.generate({"method"=>method, "args"=>args})); io.write("\n"); io.flush
  line = io.gets
  raise "no response" if line.nil?
  resp = JSON.parse(line)
  raise resp["error"] unless resp["ok"]
  resp["result"]
end
r1 = rpc_call(io, "move", 12, 100, 200)
r2 = rpc_call(io, "windows")
puts "RPC1 move -> #{r1.inspect} (#{r1.class})"
puts "RPC2 windows -> #{r2.inspect}"
puts "ROUNDTRIP_OK" if r1 == [12, 100, 200]
rescue => e
  $stderr.puts "RUBY ERROR: #{e.class}: #{e.message}"
  $stderr.puts e.backtrace.first(5).join("\n")
end
"""#
try rbEval(rubyCode)
err("DONE")
