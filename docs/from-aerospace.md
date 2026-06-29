---
title: AeroSpace から
nav_order: 4
---

[← ホーム]({{ '/' | relative_url }}) ・ [API リファレンス]({{ '/wmrc-guide' | relative_url }}) ・ [yabai から]({{ '/from-yabai' | relative_url }})

# AeroSpace から乗り換える

[AeroSpace](https://github.com/nikitabobko/AeroSpace) の
**標準的な設定が、このシステムでどう書けるか**の対応集。

## 前提: 思想の違い

- AeroSpace は **自動タイリング＋仮想ワークスペース** を持つ「完成品の WM」。`~/.aerospace.toml`
  は「その WM の挙動を選ぶ」もの。特徴的なのは、AeroSpace が **native な macOS Spaces を使わず**、
  ウィンドウを画面外へ退避することで独自のワークスペースを実装している点（private API を避ける設計）。
- 本システムは **Ruby の基盤**。ウィンドウ操作・キー入力・永続化の最小プリミティブだけを提供し、
  レイアウトやモードの「振る舞い」は**あなたが Ruby で書く**。
- したがって:
  - **キーバインド＋ウィンドウ操作（focus / move / resize / fullscreen / tile）は素直に移植できる**。
  - **`mode`（モード）は `WM.on_any_key`（リーダーキー）にそのまま対応する**。
  - **自動タイリングは付いてこない**が Ruby で組める。**ワークスペースは AeroSpace と同じ
    「画面外退避」手法を Ruby で再現できる**（private API 不要。後述）。

> キーコードは US 物理位置。一覧は [API リファレンス]({{ '/wmrc-guide' | relative_url }})。
> 修飾キーは `:cmd :shift :alt :ctrl`（fn は不可）。

## まず: 共通ヘルパー（`~/.wmrc.rb` に置く）

AeroSpace の「方向フォーカス / 方向移動 / リサイズ」をこのシステムで実現する小道具。
ジオメトリ（`WM.windows`）から方向の隣を探す純 Ruby。

```ruby
# フォーカス中ウィンドウと、その dir 方向で最も近いウィンドウを返す。dir: :left :right :up :down
def cur_and_neighbor(dir)
  wins = WM.windows
  id = WM.focused_window or return [nil, nil]
  cur = wins.find { |w| w["id"] == id } or return [nil, nil]
  cx = cur["x"] + cur["w"] / 2.0
  cy = cur["y"] + cur["h"] / 2.0
  cand = wins.reject { |w| w["id"] == id }.select do |w|
    wx = w["x"] + w["w"] / 2.0; wy = w["y"] + w["h"] / 2.0
    case dir
    when :left then wx < cx; when :right then wx > cx
    when :up   then wy < cy; when :down  then wy > cy
    end
  end
  nb = cand.min_by do |w|
    wx = w["x"] + w["w"] / 2.0; wy = w["y"] + w["h"] / 2.0
    (wx - cx)**2 + (wy - cy)**2
  end
  [cur, nb]
end

# 方向フォーカス（focus left/right/...）
def focus_dir(dir)
  _cur, nb = cur_and_neighbor(dir)
  return unless nb
  WM.activate(nb["pid"]); WM.raise_window(nb["id"])
end

# 方向移動（move：隣のウィンドウと位置を入れ替える）
def swap_dir(dir)
  cur, nb = cur_and_neighbor(dir)
  return unless cur && nb
  WM.move(cur["id"], nb["x"], nb["y"]);  WM.resize(cur["id"], nb["w"], nb["h"])
  WM.move(nb["id"],  cur["x"], cur["y"]); WM.resize(nb["id"],  cur["w"], cur["h"])
end

# リサイズ（dw, dh ポイント）
def resize_focused(dw, dh)
  id = WM.focused_window or return
  w = WM.windows.find { |x| x["id"] == id } or return
  WM.resize(id, w["w"] + dw, w["h"] + dh)
end

# 最大化 / 半分（tile は可視領域に対する割合）
def fullscreen; id = WM.focused_window; WM.tile(id, 0, 0, 1, 1) if id; end
def half(fx);   id = WM.focused_window; WM.tile(id, fx, 0, 0.5, 1) if id; end
```

## `~/.aerospace.toml` → `~/.wmrc.rb`

| `~/.aerospace.toml` | `~/.wmrc.rb` |
|---|---|
| `alt-h = 'focus left'` | `WM.on_key(0x04, [:alt]) { focus_dir(:left); true }` |
| `alt-shift-h = 'move left'` | `WM.on_key(0x04, [:shift,:alt]) { swap_dir(:left); true }` |
| `alt-f = 'fullscreen'` | `WM.on_key(0x03, [:alt]) { fullscreen; true }` |
| `alt-1 = 'workspace 1'` | 「仮想ワークスペース」レシピで対応（後述） |
| `[mode.service]` / `mode service` で入る | `WM.on_any_key` によるモード（下記） |

**モード（AeroSpace の service モード相当）** は状態変数 ＋ `on_any_key` で:

```ruby
mode = nil
WM.on_any_key do |ev|
  next false unless ev[:key_down]
  if mode == :service
    case ev[:keycode]
    when 0x0F then fullscreen; mode = nil   # r = 例として最大化（任意の操作を割り当て）
    when 0x35 then mode = nil               # Esc = mode main へ戻る
    else mode = nil
    end
    next true
  end
  # 注: 設定リロード（AeroSpace の reload-config）は Ruby からは呼べない。メニュー ▸ Reload config（⌘R）で。
  # alt-shift-; で service モードへ（; = 0x29）。修飾ビットは WM.normalize_mods で作る。
  if ev[:keycode] == 0x29 && ev[:mods] == WM.normalize_mods([:alt, :shift])
    mode = :service; puts "-- service: r=fullscreen Esc=exit"; next true
  end
  false
end
```
（より作り込んだリーダーキーの雛形は
[API リファレンスのレシピ]({{ '/wmrc-guide' | relative_url }})。）

## 仮想ワークスペース（AeroSpace と同じ「画面外退避」方式）

AeroSpace は native Spaces を使わず、隠したいウィンドウを画面外へ退避して独自のワークスペースを
実装している。これは `WM.move` だけでできるので、**private API も SIP 緩和も無しに Ruby で再現できる**。

下は最小実装。`alt-1..3` でワークスペース切替、`alt-shift-1..3` でフォーカス窓を移動。所属と復元座標は
`WM.save`/`WM.load` で再起動をまたいで保持する。

```ruby
module WS
  PARK = [-100000, -100000]   # 画面外の退避先
  NAMES = %w[1 2 3]

  class << self
    def current = WM.load("ws:current") || "1"
    def current=(n) = WM.save("ws:current", n)

    # window_id => 所属ワークスペース名
    def owner = WM.load("ws:owner") || {}
    def owner=(h) = WM.save("ws:owner", h)

    # 表示中（=current 所属、または未割り当て）の窓だけ残し、他は退避する
    def apply!
      cur = current; own = owner
      WM.windows.each do |w|
        id = w["id"]
        ws = own[id.to_s] || cur          # 未割り当て窓は current 扱い
        if ws == cur
          # 退避していた窓なら戻す（復元座標があれば使う）
          if (pos = WM.load("ws:pos:#{id}"))
            WM.move(id, pos[0], pos[1]); WM.save("ws:pos:#{id}", nil)
          end
        else
          # 別ワークスペースの窓は座標を覚えてから画面外へ
          WM.save("ws:pos:#{id}", [w["x"], w["y"]]) unless WM.load("ws:pos:#{id}")
          WM.move(id, *PARK)
        end
      end
    end

    def switch(name)
      return unless NAMES.include?(name)
      self.current = name
      apply!
    end

    # フォーカス窓を name ワークスペースへ送る
    def move_focused(name)
      id = WM.focused_window or return
      h = owner; h[id.to_s] = name; self.owner = h
      apply!
    end
  end
end

WS::NAMES.each do |n|
  WM.on_key(0x12 + WS::NAMES.index(n), [:alt])        { WS.switch(n);       true }  # alt-1/2/3
  WM.on_key(0x12 + WS::NAMES.index(n), [:alt, :shift]) { WS.move_focused(n); true }  # alt-shift-1/2/3
end
# 0x12=1, 0x13=2, 0x14=3（数字キーの並び）
```

注意点:

- これは「画面外に置いて隠す」擬似ワークスペース。Mission Control 上では全部同じ Space にいる
  （Dock の Spaces バーには出ない）。AeroSpace と同じ割り切り。
- 「最小化（`WM.minimize`）で隠す」方式に変えても良い。Dock にしまわれる代わりにアニメーションが入る。
- native の Spaces そのものを操作したい（`alt-1` で OS の Space を切り替えたい）場合は private API が
  必要で現状未対応。違いは [API リファレンス]({{ '/wmrc-guide' | relative_url }}) と
  [yabai から]({{ '/from-yabai' | relative_url }}) を参照。

## まだ 1:1 にならないもの（正直な現状）

- **自動タイリング（ツリー管理）**: 本システムは手動配置（`move`/`resize`/`tile`）。
  「常に隙間なく自動整列」は付いてこない。ただし `WM.windows` を読んで**自前のレイアウトを Ruby で
  組める**（下記）。
- **native macOS Spaces**: 上記の「画面外退避」で体験は再現できるが、OS の Space そのものの切替・
  ウィンドウ移動は private API が必要なため未対応。
- **float / managed の区別**: すべて「手動で管理」なので float の概念は無い。「動かしたくない窓は
  そのキーで触らない」だけ。

### 自前タイリングの例（手動タイル）

```ruby
# 今ある通常ウィンドウを、メイン画面の可視領域に縦グリッドで均等配置
def tile_all_columns
  wins = WM.windows
  n = wins.size
  return if n.zero?
  wins.each_with_index do |w, i|
    WM.tile(w["id"], i.to_f / n, 0.0, 1.0 / n, 1.0)
  end
end
WM.on_key(0x11, [:cmd, :alt]) { tile_all_columns; true }   # ⌘⌥T
```

---

> このページは「よくある設定」を中心にした出発点です。あなたの AeroSpace 設定で
> 「これはどう書く？」があれば Issue へ。レシピを増やしていきます。
