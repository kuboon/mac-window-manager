import AppKit
import Foundation

/// メニューバー常駐アプリ本体（Part C）。
/// 権限確認 → RubyVM 起動 → 設定ロード → イベントタップ設置 を束ねる。
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var rubyVM: RubyVM?
    private var eventTap: EventTap?

    private var userConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".wmrc.rb")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        // アクセシビリティ権限が無ければ案内して終了（許可後に再起動してもらう）。
        guard Permissions.ensureAccessibility(promptIfNeeded: true) else {
            Permissions.showAccessibilityAlert()
            return
        }
        // タイトル取得のため画面収録も確認（任意）。
        _ = Permissions.ensureScreenRecording(requestIfNeeded: false)

        startRuby()
        startEventTap()
    }

    // MARK: - メニューバー

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▦"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reload config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Edit ~/.wmrc.rb", action: #selector(editConfig), keyEquivalent: "e"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    // MARK: - Ruby

    private func startRuby() {
        guard let wasmURL = Bundle.module.url(forResource: "ruby", withExtension: "wasm") else {
            presentError("ruby.wasm がバンドルに見つかりません（make fetch-ruby / README 参照）。")
            return
        }
        do {
            let vm = try RubyVM(wasmPath: wasmURL.path)
            self.rubyVM = vm
            try loadConfig(into: vm)
        } catch {
            presentError("RubyVM の起動に失敗: \(error)")
        }
    }

    private func loadConfig(into vm: RubyVM) throws {
        // 同梱の WM ライブラリ。
        let wmLibURL = Bundle.module.url(forResource: "wm", withExtension: "rb")!
        let wmLib = try String(contentsOf: wmLibURL, encoding: .utf8)

        // 初回起動時はサンプル設定を ~/.wmrc.rb にコピー。
        if !FileManager.default.fileExists(atPath: userConfigPath),
           let defaultURL = Bundle.module.url(forResource: "default.wmrc", withExtension: "rb") {
            try? FileManager.default.copyItem(atPath: defaultURL.path, toPath: userConfigPath)
        }

        try vm.bootstrap(wmLib: wmLib, userConfigPath: userConfigPath)
    }

    @objc private func reloadConfig() {
        guard let vm = rubyVM else { return }
        do {
            // ハンドラを初期化してから再ロード。
            try vm.eval("WM.reset!")
            try loadConfig(into: vm)
        } catch {
            presentError("リロードに失敗: \(error)")
        }
    }

    @objc private func editConfig() {
        NSWorkspace.shared.openFile(userConfigPath, withApplication: "TextEdit")
    }

    // MARK: - キーイベント

    private func startEventTap() {
        let tap = EventTap { [weak self] event in
            // タップコールバック → Ruby ディスパッチ → consume 判定。
            self?.rubyVM?.dispatchKey(event) ?? false
        }
        if !tap.start() {
            presentError("イベントタップの設置に失敗（アクセシビリティ権限を確認）。")
        }
        self.eventTap = tap
    }

    // MARK: - ユーティリティ

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Ruby Window Manager"
        alert.informativeText = message
        alert.runModal()
    }
}

// エントリポイント。LSUIElement=true なのでメニューバーのみ（Dock なし）。
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
