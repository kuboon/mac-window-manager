#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// メニューバー常駐アプリ本体（Part C）。
/// 権限確認 → RubyVM 起動 → 設定ロード → イベントタップ設置 を束ねる。
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var rubyVM: RubyVM?
    private var eventTap: EventTap?
    private var dragMonitor: Any?
    private var draggedWindowID: CGWindowID?

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
        observeScreenChanges()
        observeSpaceChanges()
        observeWindowDrags()
    }

    // MARK: - Space（仮想デスクトップ）切替

    /// アクティブ Space の切替を Ruby（`WM._on_space_changed`）へ通知する。
    /// public 通知なので private API も SIP 緩和も不要。「どの Space か」は分からない
    /// （public API に無い）ので、Ruby 側は発火後に `WM.windows` で新アクティブ Space の窓を見る。
    /// NOTE: この通知は `NSWorkspace.shared.notificationCenter` 限定（既定の NotificationCenter
    ///       には来ない）。
    private func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            _ = try? self?.rubyVM?.eval("WM._on_space_changed")
        }
    }

    // MARK: - ディスプレイ構成変更

    /// 外部ディスプレイの接続/切断・配置・解像度変更を Ruby（`WM._on_screens_changed`）へ通知する。
    /// AppKit は 1 回の変更で複数回通知することがあるので、Ruby 側ハンドラは冪等に書く想定。
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            _ = try? self?.rubyVM?.eval("WM._on_screens_changed")
        }
    }

    // MARK: - ウィンドウのドラッグ（snap 用の観測フック）

    /// 他アプリのウィンドウをマウスでドラッグして離した瞬間に Ruby（`WM._on_drag_end`）へ通知する。
    /// **観測専用**（イベントは消費しない＝OS の通常移動はそのまま）。Ruby 側で端への吸着(snap)等を実装する。
    /// 動かしている窓は「ドラッグ開始時の前面ウィンドウ」とみなす。
    private func observeWindowDrags() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self = self else { return }
            switch event.type {
            case .leftMouseDragged:
                // ドラッグ中の最初のイベントで対象ウィンドウを確定（前面＝ドラッグ中の窓）。
                if self.draggedWindowID == nil {
                    self.draggedWindowID = WindowAPI.focusedWindowID()
                }
            case .leftMouseUp:
                guard let id = self.draggedWindowID else { return }
                self.draggedWindowID = nil
                // カーソルの現在位置（top-left グローバル。CG/AX と同じ座標系）。
                let p = CGEvent(source: nil)?.location ?? .zero
                _ = try? self.rubyVM?.eval("WM._on_drag_end(\(id), \(p.x), \(p.y))")
            default:
                break
            }
        }
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

    // MARK: - リソース解決

    /// SPM のリソースバンドル（`WindowManager_WindowManager.bundle`）を配置揺れに強く解決する。
    ///
    /// SwiftPM 既定の `Bundle.module`（実行ファイル target 版）は `Bundle.main.bundleURL`
    /// = **.app ルート直下**しか探さない。しかし codesign は .app ルート直下の同梱物を
    /// 許さない（"unsealed contents present in the bundle root"）。そこでバンドルは標準の
    /// `Contents/Resources/` に置き、ここで複数の候補から自前で解決する（`Bundle.module` 非依存）。
    private static let resourceBundle: Bundle? = {
        let name = "WindowManager_WindowManager.bundle"
        var bases: [URL] = []
        if let r = Bundle.main.resourceURL { bases.append(r) }                 // .app/Contents/Resources
        bases.append(Bundle.main.bundleURL)                                    // .app ルート / CLI ディレクトリ
        bases.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {  // 実行ファイル隣（CLI 実行時）
            bases.append(exe)
        }
        for base in bases {
            if let bundle = Bundle(url: base.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }()

    private func resourceURL(_ name: String, _ ext: String) -> URL? {
        Self.resourceBundle?.url(forResource: name, withExtension: ext)
    }

    // MARK: - Ruby

    private func startRuby() {
        guard let wasmURL = resourceURL("ruby", "wasm") else {
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
        guard let wmLibURL = resourceURL("wm", "rb") else {
            throw RubyVMError("wm.rb がバンドルに見つかりません")
        }
        let wmLib = try String(contentsOf: wmLibURL, encoding: .utf8)

        // 初回起動時はサンプル設定を ~/.wmrc.rb にコピー。
        if !FileManager.default.fileExists(atPath: userConfigPath),
           let defaultURL = resourceURL("default.wmrc", "rb") {
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

#else

// Linux 等の非 Apple プラットフォーム向けスタブ。
// 本体は macOS 専用だが、クロスプラットフォームなコア層（WindowManagerCore）を
// Linux 上で `swift test` できるよう、実行ファイルターゲットもビルド可能にしておく。
import Foundation

print("WindowManager is a macOS app. Build and run it on macOS (see README).")

#endif
