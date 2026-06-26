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

    # 設定リロード時にハンドラを初期化するために呼ぶ。
    def reset!
      @handlers = []
    end

    def normalize_mods(mods)
      Array(mods).reduce(0) { |acc, m| acc | (MOD[m] || 0) }
    end

    # 関心のある修飾ビットだけを抽出するマスク。
    RELEVANT_MODS = MOD.values.reduce(0, :|)

    # Swift(EventTap) から各キーイベントごとに呼ばれるディスパッチャ。
    # 戻り値 true で consume（イベントを他アプリへ渡さない）。
    def _dispatch_key(keycode, flags, key_down)
      return false unless key_down # 初期実装は keyDown のみ対象
      active_mods = flags & RELEVANT_MODS
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
  end
end
