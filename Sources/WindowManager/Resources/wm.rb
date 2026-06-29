# wm.rb — Ruby から macOS ウィンドウ操作を呼ぶための標準ライブラリ。
#
# ホスト(Swift)とは preopen 配下のファイル上の行単位 JSON-RPC で同期通信する（Part B-1）。
#   送信: {"method": "...", "args": [...]}\n
#   受信: {"ok": true, "result": ...}\n  /  {"ok": false, "error": "..."}\n
#
# NOTE: phantom fd（ホスト側でフックしただけの fd）は MRI が書き込みモードで開けない
#       （`IO.new(3,"r+")` は Errno::EINVAL）。そこで RubyVM が preopen した実ディレクトリ
#       配下のファイルを開き、本物の read-write fd を得る。その fd の I/O を RubyVM が
#       フックして RpcChannel へ橋渡しする（詳細は docs/ruby-wasm-spike.md §6）。
#
# Swift の RubyVM がブートストラップ時にこのファイルを eval する。

require "json"

module WM
  # RubyVM が preopen するゲスト側ディレクトリ（RubyVM.rpcGuestDir = "/rpc"）配下のソケット相当。
  RPC_PATH = "/rpc/sock"

  class Error < StandardError; end

  class << self
    # --- 低レベル RPC -------------------------------------------------------

    def _io
      @io ||= File.open(RPC_PATH, "w+")
    end

    def call(method, *args)
      _io.write(JSON.generate({ "method" => method, "args" => args }))
      _io.write("\n")
      _io.flush
      line = _io.gets
      raise Error, "no response from host" if line.nil?
      resp = JSON.parse(line)
      raise Error, resp["error"] unless resp["ok"]
      resp["result"]
    end

    # --- 公開 API（docs/macos-window-api.md の対応表に準拠）------------------

    # オンスクリーンの通常ウィンドウ一覧。
    # => [{ "id"=>, "pid"=>, "app"=>, "title"=>, "x"=>, "y"=>, "w"=>, "h"=>, "on_screen"=> }, ...]
    def windows
      call("windows")
    end

    # ディスプレイ一覧（top-left 原点に統一済み）。
    def screens
      call("screens")
    end

    # 起動中アプリ一覧。
    def apps
      call("apps")
    end

    # フォーカス中ウィンドウの id（無ければ nil）。
    def focused_window
      call("focused_window")
    end

    def move(window_id, x, y)   = call("move", window_id, x, y)
    def resize(window_id, w, h) = call("resize", window_id, w, h)
    def raise_window(window_id) = call("raise", window_id)
    def minimize(window_id, flag = true) = call("minimize", window_id, flag)
    def activate(pid)           = call("activate", pid)
    def hide_app(pid)           = call("hide_app", pid)

    # --- 永続ストレージ（ホスト側 JSON ファイル）----------------------------
    # 再起動をまたいで残る KV ストア。value は JSON 化可能な値（配列/ハッシュ/数値/文字列）。
    # 例: WM.save("layout:#{sig}", snapshot) / WM.load("layout:#{sig}")
    def save(key, value) = call("store_set", key, value)
    def load(key)        = call("store_get", key)

    # 便利関数: ウィンドウを指定スクリーンの可視領域に対する割合で配置する。
    # 例: tile(win_id, 0.0, 0.0, 0.5, 1.0) で左半分。
    def tile(window_id, fx, fy, fw, fh, screen: screens.first)
      return unless screen
      x = screen["visible_x"] + screen["visible_w"] * fx
      y = screen["visible_y"] + screen["visible_h"] * fy
      w = screen["visible_w"] * fw
      h = screen["visible_h"] * fh
      move(window_id, x, y)
      resize(window_id, w, h)
    end

    # --- キーイベント DSL（Part B-3）---------------------------------------

    # 修飾キー（CGEventFlags の生値に対応するビット）。
    MOD = {
      cmd:   0x100000,  # maskCommand
      shift: 0x020000,  # maskShift
      alt:   0x080000,  # maskAlternate (Option)
      ctrl:  0x040000,  # maskControl
      fn:    0x800000,  # maskSecondaryFn
    }.freeze

    # キーハンドラ登録。keycode は仮想キーコード、mods は [:cmd, :alt] 等。
    # ブロックが truthy を返すと、そのキーイベントは握りつぶされる（リマップ）。
    def on_key(keycode, mods = [], &block)
      handlers << { keycode: keycode, mods: normalize_mods(mods), block: block }
    end

    def handlers
      @handlers ||= []
    end

    # --- ディスプレイ構成変更フック ----------------------------------------
    # 外部ディスプレイの接続/切断・配置・解像度変更で呼ばれる。ブロックは現在の
    # screens 配列を 1 引数で受け取る。AppKit は 1 操作で複数回通知しうるので冪等に。
    def on_screens_changed(&block)
      screen_handlers << block
    end

    def screen_handlers
      @screen_handlers ||= []
    end

    # --- 生キーフック（モード/リーダーキー等を Ruby 側で自由に組むための最小の口）-----
    # 全キーイベントを受け取る。keyDown だけでなく keyUp / 修飾キー変化でも呼ばれる
    # （`ev[:key_down]` で判別）。`on_key` の照合より **先に** 評価され、truthy を返すと
    # そのイベントを consume して通常の `on_key` 照合をスキップする。
    # ev = { keycode:, mods:, flags:, key_down: }。
    def on_any_key(&block)
      any_handlers << block
    end

    def any_handlers
      @any_handlers ||= []
    end

    # --- ウィンドウのドラッグ&ドロップ（観測専用 / snap 用）-----------------
    # 他アプリのウィンドウをマウスでドラッグして離した瞬間に呼ばれる。
    # ブロックは ev = { window:, x:, y: } を受け取る（x,y は top-left グローバルなカーソル位置）。
    # consume はしない（OS の通常移動はそのまま）。端への吸着(snap)等を Ruby 側で実装する。
    def on_drag_end(&block)
      drag_handlers << block
    end

    def drag_handlers
      @drag_handlers ||= []
    end

    # 設定リロード時にハンドラを初期化するために呼ぶ。
    def reset!
      @handlers = []
      @screen_handlers = []
      @any_handlers = []
      @drag_handlers = []
    end

    def normalize_mods(mods)
      Array(mods).reduce(0) { |acc, m| acc | (MOD[m] || 0) }
    end

    # 関心のある修飾ビットだけを抽出するマスク。
    # 注意: fn(secondaryFn 0x800000) は **矢印キーや F キーを押すと OS が自動で立てる**ため、
    #       これを判定対象に含めると `WM.on_key(KEY_LEFT, [:cmd, :alt])` のような矢印
    #       ショートカットが「fn も押された」扱いになり一致しなくなる（numericPad 0x200000 も同様）。
    #       そこで照合には cmd/shift/alt/ctrl の 4 つだけを使う（fn は明示的な修飾キーとしては非対応）。
    RELEVANT_MODS = MOD[:cmd] | MOD[:shift] | MOD[:alt] | MOD[:ctrl]

    # Swift(EventTap) から各キーイベントごとに呼ばれるディスパッチャ。
    # 戻り値 true で consume（イベントを他アプリへ渡さない）。
    def _dispatch_key(keycode, flags, key_down)
      active_mods = flags & RELEVANT_MODS
      # 生キーフックを最優先で評価（モード/リーダーキー等はここで全キーを掴める）。
      unless any_handlers.empty?
        ev = { keycode: keycode, mods: active_mods, flags: flags, key_down: key_down }
        any_handlers.each { |h| return true if h.call(ev) }
      end
      return false unless key_down # 以降の on_key 照合は keyDown のみ対象
      handlers.each do |h|
        next unless h[:keycode] == keycode && h[:mods] == active_mods
        ev = { keycode: keycode, flags: flags, mods: active_mods }
        result = h[:block].call(ev)
        return true if result # truthy なら consume
      end
      false
    rescue => e
      warn "WM key handler error: #{e.class}: #{e.message}"
      false
    end

    # Swift(AppController) からディスプレイ構成変更時に呼ばれる。
    def _on_screens_changed
      scr = screens
      screen_handlers.each { |h| h.call(scr) }
      true
    rescue => e
      warn "WM screens handler error: #{e.class}: #{e.message}"
      false
    end

    # Swift(AppController) からウィンドウのドロップ時に呼ばれる。
    def _on_drag_end(window_id, x, y)
      ev = { window: window_id, x: x, y: y }
      drag_handlers.each { |h| h.call(ev) }
      true
    rescue => e
      warn "WM drag handler error: #{e.class}: #{e.message}"
      false
    end
  end
end
