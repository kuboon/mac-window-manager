---
title: yabai から
nav_order: 3
---

[← ホーム]({{ '/' | relative_url }}) ・ [API リファレンス]({{ '/wmrc-guide' | relative_url }}) ・ [AeroSpace から]({{ '/from-aerospace' | relative_url }})

# yabai から乗り換える

[yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/koekeishiya/skhd) の
**標準的な設定が、このシステムでどう書けるか**の対応集。

## コピペで BSP タイリング（yabai の `layout bsp` 相当）

**この module を `~/.wmrc.rb` に貼れば、yabai の自動 BSP タイリングが手に入る。**
可視領域を再帰的に二分し、長い辺を割る（yabai の自動 split と同じ挙動）。`window_gap` も付く。

```ruby
module BSP
  GAP = 8   # 窓どうし・画面端の隙間（yabai の window_gap 相当）

  class << self
    # 矩形(px)を再帰的に二分し、wins を隙間なく敷き詰める。
    # 「長い辺」を割る = yabai の自動 split（横長なら左右、縦長なら上下）。
    def layout(wins, x, y, w, h)
      return if wins.empty?
      if wins.size == 1
        WM.move(wins[0]["id"], x + GAP, y + GAP)
        WM.resize(wins[0]["id"], w - 2 * GAP, h - 2 * GAP)
        return
      end
      first, *rest = wins
      if w >= h                       # 横長 → 縦線で分割（左右）
        half = w / 2.0
        layout([first], x, y, half, h)
        layout(rest, x + half, y, w - half, h)
      else                            # 縦長 → 横線で分割（上下）
        half = h / 2.0
        layout([first], x, y, w, half)
        layout(rest, x, y + half, w, h - half)
      end
    end

    # 今の Space の通常ウィンドウを BSP で敷き詰める。
    def retile(screen: WM.screens.first)
      return unless screen
      layout(WM.windows,
             screen["visible_x"], screen["visible_y"],
             screen["visible_w"], screen["visible_h"])
    end
  end
end

# ⌘⌥Return で今の Space を BSP 整列（yabai の自動整列を手動トリガで）
WM.on_key(0x24, [:cmd, :alt]) { BSP.retile }

# 窓の抜き差しで自動再整列したい場合（Space 切替のたびに敷き直す例）:
WM.on_space_changed { BSP.retile }
```

`GAP` を変えれば `window_gap`、`layout` に渡す矩形を内側へ縮めれば padding になる。
`WM.windows` の順序を差し替えれば「マスターを大きく」等の変種も Ruby で自由に組める。

> 本システムは **Ruby の基盤**。ウィンドウ操作・キー入力・永続化の最小プリミティブだけを提供し、
> レイアウトの「振る舞い」は上の module のように**あなたが Ruby で書く**。キーバインド＋ウィンドウ操作
> （focus / warp / resize / fullscreen / tile）はそのまま移植でき、BSP も上でそのまま再現できる。
> Spaces だけは private API が要るので現状 1:1 にはならない（後述）。

> キーコードは US 物理位置。一覧は [API リファレンス]({{ '/wmrc-guide' | relative_url }})。
> 修飾キーは `:cmd :shift :alt :ctrl`（fn は不可）。

## まず: 共通ヘルパー（`~/.wmrc.rb` に置く）

yabai の「方向フォーカス / 方向 warp / リサイズ」をこのシステムで実現する小道具。
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

# 方向フォーカス（window --focus west/east/...）
def focus_dir(dir)
  _cur, nb = cur_and_neighbor(dir)
  return unless nb
  WM.activate(nb["pid"]); WM.raise_window(nb["id"])
end

# 方向移動（window --warp：隣のウィンドウと位置を入れ替える）
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

## `~/.skhdrc` → `~/.wmrc.rb`

`~/.skhdrc` の典型例（左）と等価な `~/.wmrc.rb`（右）。

| `~/.skhdrc`（yabai） | `~/.wmrc.rb` |
|---|---|
| `alt - h : yabai -m window --focus west` | `WM.on_key(0x04, [:alt]) { focus_dir(:left);  true }` |
| `alt - l : yabai -m window --focus east` | `WM.on_key(0x25, [:alt]) { focus_dir(:right); true }` |
| `alt - j : yabai -m window --focus south` | `WM.on_key(0x26, [:alt]) { focus_dir(:down);  true }` |
| `alt - k : yabai -m window --focus north` | `WM.on_key(0x28, [:alt]) { focus_dir(:up);    true }` |
| `shift + alt - h : yabai -m window --warp west` | `WM.on_key(0x04, [:shift,:alt]) { swap_dir(:left); true }` |
| `ctrl + alt - h : yabai -m window --resize left:-50:0` | `WM.on_key(0x04, [:ctrl,:alt]) { resize_focused(-50, 0); true }` |
| `alt - f : yabai -m window --toggle zoom-fullscreen` | `WM.on_key(0x03, [:alt]) { fullscreen; true }` |
| `alt - 1 : yabai -m space --focus 1` | ⏳ Spaces 未対応（後述） |

（H=0x04, J=0x26, K=0x28, L=0x25, F=0x03。`yabairc` の `layout bsp` / gaps / padding に当たる
「自動整列」は本システムには無いので、必要なら下の「自前タイリング」を参照。）

## まだ 1:1 にならないもの（正直な現状）

- **Spaces（Mission Control の仮想デスクトップ）切替**: macOS の Spaces 操作は private な
  SkyLight/CGS API が必要で、yabai も scripting addition（SIP 一部無効化）でこれを叩いている。
  本システムは現状 RPC 未提供。→ 将来プリミティブ（`WM.space_focus` 等）を足せば対応可能。
  なお「Space が**切り替わった**こと」の検出だけなら public 通知で安価に足せる（`WM.on_space_changed`
  構想）。詳細は [API リファレンス]({{ '/wmrc-guide' | relative_url }})。
  Spaces を**使わず**ワークスペースを再現する手は [AeroSpace から]({{ '/from-aerospace' | relative_url }})
  の「仮想ワークスペース」を参照（`move` で画面外退避するだけ。private API 不要）。
- **自動 BSP タイリング（ツリー管理）**: 常駐してツリーを保持し続ける「完成品の自動タイル」は無い。
  ただし冒頭の [BSP module](#コピペで-bsp-タイリングyabai-の-layout-bsp-相当) を貼れば、キー1発（や
  Space 切替フック）で yabai と同じ BSP レイアウトに敷き直せる。順序や分割ルールも Ruby で自由に変えられる。
- **float / managed の区別**: すべて「手動で管理」なので float の概念は無い。「動かしたくない窓は
  そのキーで触らない」だけ。

---

> このページは「よくある設定」を中心にした出発点です。あなたの yabai 設定で
> 「これはどう書く？」があれば Issue へ。レシピを増やしていきます。
