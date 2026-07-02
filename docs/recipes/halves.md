---
title: 半分・1/4・中央
parent: レシピ集
nav_order: 1
---

# 半分・1/4・中央（Rectangle 風）

⌘⌥+矢印で 左半分 / 右半分 / 最大化 / 中央、⌘⌥+U/I/J/K で四隅 1/4。
左右は**同じキーを連打すると 1/2 → 1/3 → 2/3 と幅がサイクル**する（Rectangle と同じ挙動）。

```ruby
module Halves
  CYCLE = [0.5, 1.0 / 3, 2.0 / 3]   # 連打で切り替わる幅（好みで [0.5, 0.7] 等に）

  class << self
    def left  = side(:left)
    def right = side(:right)

    def maximize
      with_focused { |id| WM.tile(id, 0.0, 0.0, 1.0, 1.0) }
    end

    # 中央寄せ（幅 60% × 高さ 80%）
    def center
      with_focused { |id| WM.tile(id, 0.2, 0.1, 0.6, 0.8) }
    end

    # 四隅 1/4（fx, fy は 0.0 or 0.5）
    def quarter(fx, fy)
      with_focused { |id| WM.tile(id, fx, fy, 0.5, 0.5) }
    end

    private

    # 同方向の連打で CYCLE を進める。別方向・別窓なら先頭から。
    def side(dir)
      with_focused do |id|
        @cycle ||= {}
        prev = @cycle[id]
        i = prev && prev[:dir] == dir ? (prev[:i] + 1) % CYCLE.size : 0
        fw = CYCLE[i]
        fx = dir == :left ? 0.0 : 1.0 - fw
        WM.tile(id, fx, 0.0, fw, 1.0)
        @cycle[id] = { dir: dir, i: i }
      end
    end

    def with_focused
      id = WM.focused_window
      yield id if id
    end
  end
end

# ⌘⌥ + ←/→/↑/↓ = 左 / 右 / 最大化 / 中央
WM.on_key(0x7B, [:cmd, :alt]) { Halves.left }
WM.on_key(0x7C, [:cmd, :alt]) { Halves.right }
WM.on_key(0x7E, [:cmd, :alt]) { Halves.maximize }
WM.on_key(0x7D, [:cmd, :alt]) { Halves.center }

# ⌘⌥ + U/I/J/K = 左上 / 右上 / 左下 / 右下 の 1/4
WM.on_key(0x20, [:cmd, :alt]) { Halves.quarter(0.0, 0.0) }   # U
WM.on_key(0x22, [:cmd, :alt]) { Halves.quarter(0.5, 0.0) }   # I
WM.on_key(0x26, [:cmd, :alt]) { Halves.quarter(0.0, 0.5) }   # J
WM.on_key(0x28, [:cmd, :alt]) { Halves.quarter(0.5, 0.5) }   # K
```

## カスタマイズ

- **サイクル幅**: `CYCLE` を `[0.5]` にすれば連打サイクル無し、`[0.5, 0.62, 0.38]` のような
  好みの並びにもできる。
- **中央寄せの大きさ**: `center` の `(0.2, 0.1, 0.6, 0.8)` を変える。
- サイクル状態はメモリ上（`@cycle`）に持つだけなので、Reload でリセットされる。

## 関連

- ドラッグ操作派は [ドラッグで吸着]({{ '/recipes/snap' | relative_url }}) を併用すると Rectangle 一式の置き換えになる。
- `WM.tile` の座標系は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2.3。
