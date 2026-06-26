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

# Cmd+Opt+Left … フォーカス中ウィンドウを画面の左半分へ。
WM.on_key(KEY_LEFT, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.0, 0.0, 0.5, 1.0)
  end
  true # イベントを consume（他アプリへ渡さない）
end

# Cmd+Opt+Right … 右半分へ。
WM.on_key(KEY_RIGHT, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.5, 0.0, 0.5, 1.0)
  end
  true
end

# Cmd+Opt+Up … 画面いっぱい（最大化風）。
WM.on_key(KEY_UP, [:cmd, :alt]) do
  if (id = focused)
    WM.tile(id, 0.0, 0.0, 1.0, 1.0)
  end
  true
end

puts "[wmrc] loaded: #{WM.handlers.size} key handler(s)"
