---
title: ドラッグで吸着
parent: レシピ集
nav_order: 2
---

# ドラッグで吸着（Aero Snap 風）

ウィンドウを**マウスでドラッグして画面の端や隅で離す**と、半分 / 1/4 / 最大化へ吸着する。
Windows の Aero Snap、Rectangle のドラッグ操作に相当。`WM.on_drag_end` はイベントを
consume しないので、通常のドラッグ移動とそのまま共存する（端に寄せなければ何も起きない）。

```ruby
module Snap
  EDGE = 32   # 端とみなす幅 (pt)。大きいほど吸着しやすい

  class << self
    def on_drop(ev)
      x, y = ev[:x], ev[:y]
      s = screen_at(x, y) or return
      left   = x <= s["visible_x"] + EDGE
      right  = x >= s["visible_x"] + s["visible_w"] - EDGE
      top    = y <= s["visible_y"] + EDGE
      bottom = y >= s["visible_y"] + s["visible_h"] - EDGE
      win = ev[:window]

      if    top && left     then WM.tile(win, 0.0, 0.0, 0.5, 0.5, screen: s)   # 左上 1/4
      elsif top && right    then WM.tile(win, 0.5, 0.0, 0.5, 0.5, screen: s)   # 右上 1/4
      elsif bottom && left  then WM.tile(win, 0.0, 0.5, 0.5, 0.5, screen: s)   # 左下 1/4
      elsif bottom && right then WM.tile(win, 0.5, 0.5, 0.5, 0.5, screen: s)   # 右下 1/4
      elsif left            then WM.tile(win, 0.0, 0.0, 0.5, 1.0, screen: s)   # 左半分
      elsif right           then WM.tile(win, 0.5, 0.0, 0.5, 1.0, screen: s)   # 右半分
      elsif top             then WM.tile(win, 0.0, 0.0, 1.0, 1.0, screen: s)   # 上端 = 最大化
      end
      # どの端でもなければ何もしない（ドロップ位置のまま）
    end

    private

    # カーソル (x, y) が乗っているスクリーン（マルチモニタ対応。外れていれば先頭）
    def screen_at(x, y)
      WM.screens.find { |s|
        x >= s["x"] && x < s["x"] + s["w"] &&
        y >= s["y"] && y < s["y"] + s["h"]
      } || WM.screens.first
    end
  end
end

WM.on_drag_end { |ev| Snap.on_drop(ev) }
```

## カスタマイズ

- **当たり判定**: `EDGE` を広げる/狭める。割合で判定したい場合は
  [列・行・メイン+スタック]({{ '/recipes/tiles' | relative_url }})の `snap_on_drop`（画面の 15% で判定）を参照。
- **ゾーンの意味**: `if/elsif` の割り当てを変えるだけ。「下端 = 中央小窓」なども自由。
- **吸着後に元に戻したい**: [半分・1/4・中央]({{ '/recipes/halves' | relative_url }})のキー操作を
  併用するか、ドロップ前の座標を `WM.save` に控えて戻すキーを足す。

## 関連

- `WM.on_drag_end` の仕様は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2.8
  （1 ドラッグにつきドロップ時 1 回・観測専用）。
