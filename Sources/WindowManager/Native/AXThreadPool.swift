#if canImport(AppKit)
import Foundation

/// アプリ（pid）ごとの専用スレッドで Accessibility 呼び出しを実行するためのプール。
///
/// **なぜ必要か**: AX の各 API は対象アプリのメインスレッドへの同期 IPC で実装されており、
/// 相手アプリがビジー／ハング／モーダル表示中だと**呼び出し側が数秒単位でブロックされる**。
/// このアプリは Ruby → fd 3 → `RpcBridge.dispatch` をメインスレッドで同期実行する設計なので、
/// AX をメインスレッドで直接叩くと**アプリ 1 つのハングでウィンドウマネージャ全体（キー
/// ハンドラを含む）が停止する**。
///
/// そこで pid ごとに RunLoop を持つ専用スレッドを立て、`run` は
/// 「そのスレッドへ投げて、タイムアウト付きで待つ」形にする。タイムアウトした呼び出しは
/// `nil` を返し、ブロックされるのは高々 `timeout` の間だけになる。
/// 投げたブロック自体は相手が応答すればいずれ完走するが、結果は破棄される。
///
/// 同一 pid への呼び出しはその pid のスレッド上で**直列化**される（AX の要求順が保たれる）。
/// 別 pid への呼び出しは互いにブロックしない。
enum AXThreadPool {

    /// 通常の待ち時間。健全なアプリの AX 呼び出しは数 ms で返る。
    static let defaultTimeout: TimeInterval = 0.2

    /// 反応しないと判定したアプリに対する短縮待ち時間。
    /// 完全に諦めるのではなく毎回この短さで打診し、復帰したら通常運用へ戻す。
    static let probeTimeout: TimeInterval = 0.025

    /// この回数だけ連続でタイムアウトしたら「反応しないアプリ」と見なす。
    static let unresponsiveThreshold = 3

    /// システム全体の AX 要素（`AXUIElementCreateSystemWide`）用の擬似 pid。
    /// 実プロセスの pid は 1 以上なので衝突しない。
    static let systemWidePID: pid_t = 0

    private static let lock = NSLock()
    private static var threads: [pid_t: AXAppThread] = [:]

    /// `body` を pid 専用スレッドで実行し、`timeout` 以内に完了すればその戻り値を返す。
    /// 間に合わなければ `nil`（＝呼び出し側は「取得できなかった」として扱う）。
    static func run<T>(pid: pid_t,
                       timeout: TimeInterval = defaultTimeout,
                       _ body: @escaping () -> T) -> T? {
        thread(for: pid).run(timeout: timeout, body)
    }

    /// アプリ終了時などにスレッドを畳む。
    static func drop(pid: pid_t) {
        lock.lock()
        let victim = threads.removeValue(forKey: pid)
        lock.unlock()
        victim?.stop()
    }

    private static func thread(for pid: pid_t) -> AXAppThread {
        lock.lock()
        if let existing = threads[pid] {
            lock.unlock()
            return existing
        }
        // 新規に立てるついでに、終了済みプロセスのスレッドを掃除する。
        // kill(pid, 0) は「存在確認」。ESRCH のときだけ終了済みと判断する
        //（EPERM は他ユーザのプロセスで、生きてはいる）。
        let dead = threads.keys.filter { $0 != systemWidePID && kill($0, 0) != 0 && errno == ESRCH }
        var victims: [AXAppThread] = []
        for deadPID in dead {
            if let victim = threads.removeValue(forKey: deadPID) { victims.append(victim) }
        }
        let created = AXAppThread(pid: pid)
        threads[pid] = created
        lock.unlock()
        victims.forEach { $0.stop() }
        return created
    }
}

/// 1 つの pid に対応する RunLoop 付きワーカースレッド。
private final class AXAppThread {
    private let pid: pid_t
    private var loop: CFRunLoop?
    private let loopReady = DispatchSemaphore(value: 0)
    private var consecutiveTimeouts = 0

    init(pid: pid_t) {
        self.pid = pid
        // self を強参照で捕まえる。スレッドが動いている間だけこのオブジェクトが生き、
        // `stop()` で RunLoop を止めるとクロージャが終わって解放される。
        let thread = Thread {
            self.loop = CFRunLoopGetCurrent()
            // ソースを 1 つ持たせないと CFRunLoopRun が即座に戻ってしまう。
            RunLoop.current.add(NSMachPort(), forMode: .default)
            self.loopReady.signal()
            CFRunLoopRun()
        }
        thread.name = "wm.ax.\(pid)"
        // キー入力に同期して走るので、応答性を優先する。
        thread.qualityOfService = .userInitiated
        thread.start()
        loopReady.wait()
    }

    /// 反応しないアプリと判定されている間は短い打診に切り替える。
    private var isUnresponsive: Bool {
        consecutiveTimeouts >= AXThreadPool.unresponsiveThreshold
    }

    func run<T>(timeout: TimeInterval, _ body: @escaping () -> T) -> T? {
        guard let loop else { return nil }
        let budget = isUnresponsive ? min(timeout, AXThreadPool.probeTimeout) : timeout

        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) {
            box.fulfill(body())
            done.signal()
        }
        CFRunLoopWakeUp(loop)

        if done.wait(timeout: .now() + budget) == .timedOut {
            consecutiveTimeouts += 1
            if consecutiveTimeouts == AXThreadPool.unresponsiveThreshold {
                NSLog("[wm] pid \(pid) の AX 応答が \(AXThreadPool.unresponsiveThreshold) 回連続でタイムアウトしました。以後は短時間だけ打診します。")
            }
            _ = box.abandon()
            return nil
        }
        consecutiveTimeouts = 0
        return box.abandon()
    }

    func stop() {
        guard let loop else { return }
        CFRunLoopStop(loop)
        self.loop = nil
    }
}

/// ワーカースレッドとタイムアウトした呼び出し元の間で結果を安全に受け渡す箱。
/// タイムアウト後に遅れて到着した結果は捨てる。
private final class ResultBox<T> {
    private let lock = NSLock()
    private var value: T?
    private var abandoned = false

    func fulfill(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !abandoned else { return }
        value = newValue
    }

    /// 現在の値を取り出し、以後の `fulfill` を無効化する。
    @discardableResult
    func abandon() -> T? {
        lock.lock()
        defer { lock.unlock() }
        abandoned = true
        return value
    }
}
#endif
