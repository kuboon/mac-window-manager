#if canImport(AppKit)
import Darwin
import Foundation

/// CLI ⇄ アプリ の制御チャネル（ローカル Unix domain socket）。
///
/// 目的: `~/.wmrc.rb` で定義した func / module メソッドを **CLI から呼べる**ようにする。
/// 動いているメニューバーアプリ（＝唯一の RubyVM を保持）へ、別プロセスの CLI から
/// Ruby コード 1 片を送り、`eval` した結果文字列を受け取る。private API も特別な権限も不要
/// （同一マシン内のローカル通信のみ）。
///
/// ワイヤ規約はごく単純:
///   - クライアント: リクエストを書き込み → `shutdown(SHUT_WR)` で送信完了(EOF)を伝える
///   - サーバ:       EOF まで読み切ったものを 1 リクエストとして処理 → 結果を書いて close
/// 改行区切りに悩まないよう「EOF = リクエスト終端」とする（コードも結果も複数行で安全）。
///
/// リクエストは「1 行目 = コマンド動詞、2 行目以降 = 引数」:
///   - `eval\n<ruby code>` … コードを eval して結果(inspect)を返す
///   - `reload`            … `~/.wmrc.rb` を再読み込み（メニューの Reload config と同じ）
enum ControlChannel {
    /// ソケットパス。CLI とアプリで同じ規則で決める。`/tmp` を使うのは sun_path(104B) に
    /// 収めるため（`/var/folders/...` の一時ディレクトリは長すぎて溢れうる）。
    static var socketPath: String { "/tmp/wmrc-\(NSUserName()).sock" }

    /// リクエストを「動詞」と「引数」に分ける（1 行目が動詞、残りが引数）。
    static func parse(_ request: String) -> (verb: String, arg: String) {
        if let nl = request.firstIndex(of: "\n") {
            return (String(request[request.startIndex..<nl]),
                    String(request[request.index(after: nl)...]))
        }
        return (request.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
}

/// アドレス（sockaddr_un）を組み立てる共通ヘルパ。パスが sun_path に収まらなければ nil。
private func makeUnixSockaddr(_ path: String) -> (addr: sockaddr_un, len: socklen_t)? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cPath = path.utf8CString                       // NUL 終端込み
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard cPath.count <= capacity else { return nil }  // 溢れるなら失敗
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
        rawPtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
            cPath.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!, count: cPath.count)
            }
        }
    }
    return (addr, socklen_t(MemoryLayout<sockaddr_un>.size))
}

/// 書き込み先が閉じても SIGPIPE でプロセスごと落とさないためのフラグ。
private func silenceSIGPIPE(_ fd: Int32) {
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
}

// MARK: - サーバ（アプリ内）

/// アプリ側で待ち受ける制御ソケット。受信した Ruby コードを `handler` へ渡し、その戻り値を応答する。
/// `handler` は**任意のスレッドから**呼ばれるので、呼び出し側でメインスレッドへ hop すること
/// （RubyVM/ネイティブ API はメインスレッド前提）。
final class ControlSocketServer {
    private let listenFD: Int32
    private let handler: (String) -> String
    private var running = false

    /// バインド + listen まで済ませる。既存ソケット残骸は掃除する。失敗時は nil。
    init?(handler: @escaping (String) -> String) {
        self.handler = handler
        let path = ControlChannel.socketPath
        unlink(path)  // 前回異常終了などの残骸を除去

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return nil }
        guard var sock = makeUnixSockaddr(path) else { close(listenFD); return nil }

        let bound = withUnsafePointer(to: &sock.addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, sock.len) }
        }
        guard bound == 0 else { close(listenFD); return nil }
        chmod(path, 0o600)  // 所有ユーザのみ

        guard listen(listenFD, 4) == 0 else { close(listenFD); unlink(path); return nil }
    }

    /// accept ループをバックグラウンドスレッドで回す。
    func start() {
        running = true
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while running {
            let client = accept(listenFD, nil, nil)
            if client < 0 { if running { continue } else { break } }
            silenceSIGPIPE(client)
            serve(client)
        }
    }

    /// 1 接続 = 1 リクエスト。EOF まで読み → handler → 結果を書いて close。
    private func serve(_ client: Int32) {
        defer { close(client) }
        var request = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let cap = buf.count
        while true {
            let n = read(client, &buf, cap)
            if n <= 0 { break }
            request.append(contentsOf: buf[0..<n])
        }
        let code = String(decoding: request, as: UTF8.self)
        var response = handler(code)
        if !response.hasSuffix("\n") { response += "\n" }
        writeAll(client, Array(response.utf8))
    }

    private func writeAll(_ fd: Int32, _ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress!.advanced(by: off), buf.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    func stop() {
        running = false
        close(listenFD)
        unlink(ControlChannel.socketPath)
    }
}

// MARK: - クライアント（CLI 実行時）

enum ControlSocketClient {
    /// 起動中アプリの制御ソケットへ 1 リクエストを送り、結果文字列を返す。
    /// 接続できない（アプリ未起動 等）場合は nil。
    static func send(_ request: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        silenceSIGPIPE(fd)
        guard var sock = makeUnixSockaddr(ControlChannel.socketPath) else { return nil }

        let connected = withUnsafePointer(to: &sock.addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, sock.len) }
        }
        guard connected == 0 else { return nil }

        let payload = Array(request.utf8)
        payload.withUnsafeBufferPointer { buf in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress!.advanced(by: off), buf.count - off)
                if n <= 0 { break }
                off += n
            }
        }
        shutdown(fd, SHUT_WR)  // 送信完了 = EOF をサーバへ

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let cap = buf.count
        while true {
            let n = read(fd, &buf, cap)
            if n <= 0 { break }
            response.append(contentsOf: buf[0..<n])
        }
        return String(decoding: response, as: UTF8.self)
    }
}

// MARK: - CLI 引数のパース

enum CLI {
    /// argv から制御ソケットへ送るリクエストを組み立てる。
    /// CLI コマンドでなければ nil を返す（＝通常のメニューバーアプリとして起動する）。
    ///   `eval <ruby...>` / `--eval <ruby...>` / `-e <ruby...>` … Ruby を eval
    ///   `reload`                                              … 設定を再読み込み
    static func requestFromArguments(_ argv: [String]) -> String? {
        let args = Array(argv.dropFirst())   // argv[0] は実行ファイルパス
        guard let verb = args.first else { return nil }
        switch verb {
        case "eval", "--eval", "-e":
            // 残りを 1 スペースで連結（クォートで 1 引数に纏めても複数語でも動く）。
            return "eval\n" + args.dropFirst().joined(separator: " ")
        case "reload":
            return "reload"
        default:
            return nil   // 未知の引数は無視してアプリ起動（launchd/Finder の -psn_… 等を壊さない）
        }
    }
}
#endif
