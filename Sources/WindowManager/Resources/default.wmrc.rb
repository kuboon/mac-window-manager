# https://kuboon.github.io/mac-window-manager/
#
# default.wmrc.rb — 同梱のサンプル設定。
#
# 初回起動時にホームディレクトリへ ~/.wmrc.rb としてコピーされ、以後はそれを編集して
# メニューバーの「Reload config」で再読み込みする（Swift の再ビルドは不要）。
#
# このファイルは WM ライブラリ(wm.rb)が読み込まれた後に eval される。

# よく使う仮想キーコード（US 配列）。詳細は Carbon HIToolbox/Events.h を参照。
KEY_LEFT  = 0x7B
KEY_RIGHT = 0x7C
KEY_UP    = 0x7E
KEY_DOWN  = 0x7D

# 最前面（フォーカス中）ウィンドウを取得するヘルパ。
def focused
  WM.focused_window
end

# NOTE: on_key にマッチしたキーは**デフォルトで consume される**（他アプリへ渡さない）。
#       末尾に true を書く必要はない。OS の通常動作を残したいときだけブロックで false を返す。

# Cmd+Opt+Left … フォーカス中ウィンドウを画面の左半分へ。
WM.on_key(KEY_LEFT, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.0, 0.0, 0.5, 1.0)
  end
end

# Cmd+Opt+Right … 右半分へ。
WM.on_key(KEY_RIGHT, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.5, 0.0, 0.5, 1.0)
  end
end

# Cmd+Opt+Up … 画面いっぱい（最大化風）。
WM.on_key(KEY_UP, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.0, 0.0, 1.0, 1.0)
  end
end

# --- ディスプレイ構成ごとのレイアウト保存/復元 -------------------------------
# 再起動や外部ディスプレイ抜き差しの後、Cmd+Opt+R で位置を復元できる。
# レイアウトは「ディスプレイ構成（画面名）」をキーに保存されるので、ノート単体と
# ドック時で別々のレイアウトを持てる。

KEY_S = 0x01  # S
KEY_R = 0x0F  # R

# 現在のディスプレイ構成を表すキー。
def layout_signature
  WM.screens.map { |s| s["name"] }.sort.join(" | ")
end

# Cmd+Opt+S … 現在の全ウィンドウ位置を、今のディスプレイ構成キーで保存。
WM.on_key(KEY_S, [:cmd, :alt]) do
  snapshot = WM.windows.map do |w|
    { "app" => w["app"], "title" => w["title"],
      "x" => w["x"], "y" => w["y"], "w" => w["w"], "h" => w["h"] }
  end
  WM.save("layout:#{layout_signature}", snapshot)
  puts "[wmrc] saved #{snapshot.size} windows for [#{layout_signature}]"
end

# Cmd+Opt+R … 保存レイアウトを復元。app + title でウィンドウを照合して move/resize。
# （CGWindowID は再起動で変わるため id ではなく app/title で照合する。
#   title が変わっていたら同じアプリの最初のウィンドウで代替する。）
WM.on_key(KEY_R, [:cmd, :alt]) do
  saved = WM.load("layout:#{layout_signature}") || []
  current = WM.windows
  restored = 0
  saved.each do |s|
    win = current.find { |w| w["app"] == s["app"] && w["title"] == s["title"] } ||
          current.find { |w| w["app"] == s["app"] }
    next unless win
    WM.move(win["id"], s["x"], s["y"])
    WM.resize(win["id"], s["w"], s["h"])
    restored += 1
  end
  puts "[wmrc] restored #{restored}/#{saved.size} windows for [#{layout_signature}]"
end

# --- 外部ディスプレイ接続/切断で自動モード切替 -------------------------------
# 構成が変わるたびに呼ばれる。ここでモードを分岐できる（冪等に書くこと）。
WM.on_screens_changed do |screens|
  puts "[wmrc] screens changed -> #{screens.size} display(s): [#{layout_signature}]"
  # 例: 構成が変わったら、その構成の保存レイアウトがあれば自動適用したい場合は
  #     上の復元と同じ処理をここで呼ぶ（今回は手動 Cmd+Opt+R 方針なのでコメントのまま）。
end

puts "[wmrc] loaded: #{WM.handlers.size} key handler(s), #{WM.screen_handlers.size} screen handler(s)"
