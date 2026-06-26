import Foundation
import SystemPackage
import WasmKit
import WasmKitWASI

// Usage: rbexp <wasm> <mode> [needle]
//   imports | exports [needle] | puts
let path = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "list"

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let engine = Engine()
let store = Store(engine: engine)

err("parsing \(path) ...")
let module = try parseWasm(filePath: FilePath(path))

func sig(_ t: FunctionType) -> String {
    func vt(_ v: ValueType) -> String {
        switch v { case .i32: return "i32"; case .i64: return "i64"
                   case .f32: return "f32"; case .f64: return "f64"; default: return "v" }
    }
    return "(\(t.parameters.map(vt).joined(separator: ","))) -> (\(t.results.map(vt).joined(separator: ",")))"
}

if mode == "imports" {
    var byModule: [String: [String]] = [:]
    for imp in module.imports {
        var d = "?"
        if case .function(let ti) = imp.descriptor { d = sig(module.types[Int(ti)]) }
        byModule[imp.module, default: []].append("\(imp.name) \(d)")
    }
    for (m, names) in byModule.sorted(by: { $0.key < $1.key }) {
        print("=== \(m)  (\(names.count)) ===")
        for n in names.sorted() { print("  \(n)") }
    }
    exit(0)
}
if mode == "exports" {
    let needle = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
    for exp in module.exports where needle.isEmpty || exp.name.contains(needle) { print("  \(exp.name)") }
    exit(0)
}

// ---- mode == "puts": full host shim + WIT canonical-ABI init/eval ----

let wasi = try WASIBridgeToHost(args: ["ruby"], environment: [:],
                                preopens: ["/": NSHomeDirectory()])
var imports = Imports()
wasi.link(to: &imports, store: store)

// Simple handle table for rb-abi-value resources created by the guest.
var reps: [UInt32: UInt32] = [:]
var handleCounter: UInt32 = 0

func def(_ mod: String, _ name: String, _ p: [ValueType], _ r: [ValueType],
         _ body: @escaping (Caller, [Value]) throws -> [Value]) {
    imports.define(module: mod, name: name,
                   Function(store: store, parameters: p, results: r, body: body))
}

// Auto-generate host imports for every non-WASI import, matching the exact
// (decorated) names and resolved signatures from the module itself.
for imp in module.imports where imp.module == "canonical_abi" || imp.module == "rb-js-abi-host" {
    guard case .function(let ti) = imp.descriptor else { continue }
    let ft = module.types[Int(ti)]
    let mod = imp.module, name = imp.name
    if name.hasPrefix("resource_new_rb-abi-value") {
        def(mod, name, ft.parameters, ft.results) { _, args in
            handleCounter += 1; reps[handleCounter] = args[0].i32; return [.i32(handleCounter)]
        }
    } else if name.hasPrefix("resource_get_rb-abi-value") {
        def(mod, name, ft.parameters, ft.results) { _, args in [.i32(reps[args[0].i32] ?? 0)] }
    } else {
        // Generic stub: log if hit, return zeros of the right core types.
        def(mod, name, ft.parameters, ft.results) { _, _ in
            err("[STUB \(mod).\(name) CALLED]")
            return ft.results.map { t -> Value in
                switch t { case .i64: return .i64(0); case .f32: return .f32(0)
                           case .f64: return .f64(0); default: return .i32(0) }
            }
        }
    }
}

err("instantiating ...")
let instance = try module.instantiate(store: store, imports: imports)
err("instantiated OK")

// Export names in this build are decorated with their WIT signature, e.g.
// "rb-eval-string-protect: func(str: string) -> ...". Look up by prefix.
func exportFn(_ prefix: String) -> Function? {
    for exp in module.exports where exp.name.hasPrefix(prefix) {
        if let f = instance.exports[function: exp.name] { return f }
    }
    return nil
}

guard let memory = instance.exports[memory: "memory"] else { fatalError("no memory export") }
func writeBytes(_ ptr: UInt32, _ bytes: [UInt8]) {
    memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: bytes.count) { buf in
        for (i, b) in bytes.enumerated() { buf[i] = b }
    }
}
func readU32(_ ptr: UInt32) -> UInt32 {
    var v: UInt32 = 0
    memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: 4) { buf in
        for i in 0..<4 { v |= UInt32(buf[i]) << (8 * i) }
    }
    return v
}
func writeU32(_ ptr: UInt32, _ val: UInt32) {
    writeBytes(ptr, (0..<4).map { UInt8((val >> (8 * $0)) & 0xff) })
}

// canonical realloc allocator
guard let realloc = exportFn("cabi_realloc") else { fatalError("no cabi_realloc") }
func alloc(_ size: Int, align: Int = 1) throws -> UInt32 {
    let r = try realloc([.i32(0), .i32(0), .i32(UInt32(align)), .i32(UInt32(size))])
    return r[0].i32
}
func lowerString(_ s: String) throws -> (UInt32, UInt32) {
    let bytes = Array(s.utf8)
    let p = try alloc(bytes.count, align: 1)
    writeBytes(p, bytes)
    return (p, UInt32(bytes.count))
}

func dumpType(_ name: String) {
    if let f = exportFn(name) { err("  \(name): \(sig(f.type))") }
}
err("--- core signatures ---")
for n in ["_initialize", "ruby-init-loadpath", "ruby-init", "rb-eval-string-protect", "cabi_realloc"] {
    dumpType(n)
}

// 1. _initialize
if let initialize = exportFn("_initialize") {
    _ = try initialize(); err("_initialize done")
}
// 2. ruby-init(args: list<string>)  -- mirrors @ruby/wasm-wasi initialize():
//    only rubyInit is called (loadpath happens inside); args are NUL-terminated.
if let rubyInit = exportFn("ruby-init:") {
    let argv = ["ruby.wasm\u{0}", "-EUTF-8\u{0}", "-e_=0\u{0}"]
    var descs: [(UInt32, UInt32)] = []
    for a in argv { descs.append(try lowerString(a)) }
    let listPtr = try alloc(descs.count * 8, align: 4)
    for (i, d) in descs.enumerated() {
        writeU32(listPtr + UInt32(i * 8), d.0)
        writeU32(listPtr + UInt32(i * 8 + 4), d.1)
    }
    _ = try rubyInit([.i32(listPtr), .i32(UInt32(descs.count))])
    err("ruby-init done")
}

// 4. rb-eval-string-protect(str) -> tuple<handle, s32> via indirect return
guard let evalFn = exportFn("rb-eval-string-protect") else {
    fatalError("no rb-eval-string-protect")
}
err("eval core sig: \(sig(evalFn.type))")

@discardableResult
func rbEval(_ code: String, _ label: String) throws -> (handle: UInt32, state: UInt32) {
    let (cp, cl) = try lowerString(code)
    let results = try evalFn([.i32(cp), .i32(cl)])
    let retptr = results[0].i32
    let handle = readU32(retptr)
    let state = readU32(retptr + 4)
    err("[\(label)] handle=\(handle) state=\(state) (state!=0 => exception raised)")
    return (handle, state)
}

// (a) plain puts + interpolation
try rbEval(#"$stdout.sync = true; puts "HELLO from ruby.wasm on WasmKit (Linux); RUBY=#{RUBY_VERSION}; 2+3=#{2+3}""#, "puts")
// (b) VM state PERSISTENCE across separate eval calls (key-handler registry depends on this)
try rbEval("$counter = 40", "set-state")
try rbEval(#"puts "persisted: $counter + 2 = #{$counter + 2}"; $stdout.flush"#, "read-state")
// (c) exception path: state must be non-zero so the host can detect raised errors
try rbEval(#"raise "intentional boom""#, "raise")
// (d) read a Ruby String result back into Swift via rstring-ptr (+ cabi_post cleanup).
//     This is how the host turns an eval result into a Swift value (e.g. the
//     consume decision for key remapping: eval `expr ? "1" : "0"` then read it).
func readU8Len(_ ptr: UInt32, _ len: UInt32) -> String {
    var bytes = [UInt8](repeating: 0, count: Int(len))
    memory.withUnsafeMutableBufferPointer(offset: UInt(ptr), count: Int(len)) { buf in
        for i in 0..<Int(len) { bytes[i] = buf[i] }
    }
    return String(decoding: bytes, as: UTF8.self)
}
if let rstringPtr = exportFn("rstring-ptr"),
   let cabiPost = instance.exports[function: "cabi_post_rstring-ptr"] {
    func rubyString(_ handle: UInt32) throws -> String {
        let r = try rstringPtr([.i32(handle)])     // -> i32 retptr to (ptr,len)
        let area = r[0].i32
        let s = readU8Len(readU32(area), readU32(area + 4))
        _ = try cabiPost([.i32(area)])             // free the lifted string
        return s
    }
    // host evaluates an expression that reduces to a definite string marker
    let res = try rbEval(#"(3 > 2 ? "CONSUME" : "PASS")"#, "truthy-as-string")
    let lifted = try rubyString(res.handle)
    err("lifted Ruby String result = \"\(lifted)\"  (=> host can read consume decision)")
}
err("DONE")
