---
title: yabai から
nav_order: 3
---

[← ホーム]({{ '/' | relative_url }}) ・ [API リファレンス]({{ '/wmrc-guide' | relative_url }}) ・ [AeroSpace から]({{ '/from-aerospace' | relative_url }})

# yabai から乗り換える

[yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/koekeishiya/skhd) の
**標準的な設定が、このシステムでどう書けるか**の対応集。

## 前提: 思想の違い

- yabai は **自動タイリング（BSP ツリー）** を持つ「完成品の WM」。設定ファイルは「その WM の挙動を選ぶ」もの。
  さらに scripting addition を入れると Spaces 操作まで踏み込む（SIP の一部無効化が前提）。
- 本システムは **Ruby の基盤**。ウィンドウ操作・キー入力・永続化の最小プリミティブだけを提供し、
  レイアウトやモードの「振る舞い」は**あなたが Ruby で書く**。
- したがって:
  - **キーバインド＋ウィンドウ操作（focus / warp / resize / fullscreen / tile）は素直に移植できる**。
  - **自動 BSP タイリングと Spaces は 1:1 にはならない**（後述）。前者は Ruby で自前のレイアウトを組める。
    後者は private API（yabai と同じ世界）が必要なので現状プリミティブ未提供。

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
- **自動 BSP タイリング（ツリー管理）**: 本システムは手動配置（`move`/`resize`/`tile`）。
  「常に隙間なく自動整列」は付いてこない。ただし `WM.windows` を読んで**自前のレイアウトを Ruby で
  組める**（下記）。
- **float / managed の区別**: すべて「手動で管理」なので float の概念は無い。「動かしたくない窓は
  そのキーで触らない」だけ。

### 自前タイリングの例（手動 BSP もどき）

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

> このページは「よくある設定」を中心にした出発点です。あなたの yabai 設定で
> 「これはどう書く？」があれば Issue へ。レシピを増やしていきます。
