---
title: マルチディスプレイ
parent: レシピ集
nav_order: 7
---

# マルチディスプレイ（次の画面へ投げる）

**⌘⌥N で次のディスプレイへ、⌘⌥B で前のディスプレイへ**、フォーカス窓を移動する。
移動先でも「可視領域に対する相対位置・相対サイズ」を保つので、左半分に置いた窓は
移動先でも左半分になる。

```ruby
module Displays
  class << self
    # フォーカス窓を step 個先のディスプレイへ（相対位置・相対サイズを維持）
    def throw(step = 1)
      id = WM.focused_window or return
      win = WM.windows.find { |w| w["id"] == id } or return
      scr = WM.screens
      return if scr.size < 2
      src = scr[index_of(win, scr)]
      dst = scr[(index_of(win, scr) + step) % scr.size]
      fx = (win["x"] - src["visible_x"]) / src["visible_w"]
      fy = (win["y"] - src["visible_y"]) / src["visible_h"]
      fw = win["w"] / src["visible_w"]
      fh = win["h"] / src["visible_h"]
      WM.tile(id, fx.clamp(0.0, 0.95), fy.clamp(0.0, 0.95),
              fw.clamp(0.05, 1.0), fh.clamp(0.05, 1.0), screen: dst)
    end

    private

    # 窓の中心が乗っているスクリーンの index（どこにも乗っていなければ 0）
    def index_of(win, scr)
      cx = win["x"] + win["w"] / 2.0
      cy = win["y"] + win["h"] / 2.0
      scr.index { |s|
        cx >= s["x"] && cx < s["x"] + s["w"] &&
        cy >= s["y"] && cy < s["y"] + s["h"]
      } || 0
    end
  end
end

WM.on_key(0x2D, [:cmd, :alt]) { Displays.throw(1)  }   # ⌘⌥N 次へ
WM.on_key(0x0B, [:cmd, :alt]) { Displays.throw(-1) }   # ⌘⌥B 前へ
```

## カスタマイズ

- **移動先で最大化したい**: `WM.tile(id, 0.0, 0.0, 1.0, 1.0, screen: dst)` に差し替え。
- **特定ディスプレイへ直行**: `dst = scr[1]` のように固定 index で呼ぶキーを足す。
  ディスプレイの並びは `WM.screens`（`"name"` で判別できる）。
- ディスプレイ抜き差しに反応して配置し直したい場合は
  [レイアウト保存と復元]({{ '/recipes/layouts' | relative_url }})と組み合わせる。

## 関連

- 座標系（top-left 統一・`visible_*`）は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §1。
