---
title: 方向フォーカスと入れ替え
parent: レシピ集
nav_order: 6
---

# 方向フォーカスと入れ替え（vim 風 HJKL）

- **⌥H/J/K/L** … 左/下/上/右にある一番近いウィンドウへフォーカス移動
- **⌥⇧H/J/K/L** … その方向の隣ウィンドウと位置・サイズを交換（yabai の warp）
- **⌥⌃H/L** … フォーカス窓の幅を −50 / +50 pt
- **⌥Tab** … 同じアプリのウィンドウを順に巡回

マウスに手を伸ばさず窓を渡り歩くための一式。「近さ」はウィンドウ中心どうしの距離で判定する。

```ruby
module Focus
  class << self
    # dir: :left :right :up :down
    def focus(dir)
      nb = neighbor(dir) or return
      WM.activate(nb["pid"])
      WM.raise_window(nb["id"])
    end

    # dir 方向の隣ウィンドウと位置・サイズを入れ替える
    def swap(dir)
      cur = current or return
      nb = neighbor(dir) or return
      WM.move(cur["id"], nb["x"], nb["y"])
      WM.resize(cur["id"], nb["w"], nb["h"])
      WM.move(nb["id"], cur["x"], cur["y"])
      WM.resize(nb["id"], cur["w"], cur["h"])
    end

    # フォーカス窓を相対リサイズ
    def resize(dw, dh)
      cur = current or return
      WM.resize(cur["id"], cur["w"] + dw, cur["h"] + dh)
    end

    # 同じアプリのウィンドウを順に巡回（⌘` の代わり）
    def cycle_same_app
      cur = current or return
      same = WM.windows.select { |w| w["pid"] == cur["pid"] }
      return if same.size < 2
      i = same.index { |w| w["id"] == cur["id"] } || 0
      nxt = same[(i + 1) % same.size]
      WM.raise_window(nxt["id"])
    end

    private

    def current
      id = WM.focused_window or return nil
      WM.windows.find { |w| w["id"] == id }
    end

    # dir 方向にあるウィンドウのうち、中心が一番近いもの
    def neighbor(dir)
      cur = current or return nil
      cx = cur["x"] + cur["w"] / 2.0
      cy = cur["y"] + cur["h"] / 2.0
      cand = WM.windows.reject { |w| w["id"] == cur["id"] }.select do |w|
        wx = w["x"] + w["w"] / 2.0
        wy = w["y"] + w["h"] / 2.0
        case dir
        when :left  then wx < cx
        when :right then wx > cx
        when :up    then wy < cy
        when :down  then wy > cy
        end
      end
      cand.min_by do |w|
        wx = w["x"] + w["w"] / 2.0
        wy = w["y"] + w["h"] / 2.0
        (wx - cx)**2 + (wy - cy)**2
      end
    end
  end
end

# ⌥ + H/J/K/L = フォーカス移動
WM.on_key(0x04, [:alt]) { Focus.focus(:left)  }   # H
WM.on_key(0x26, [:alt]) { Focus.focus(:down)  }   # J
WM.on_key(0x28, [:alt]) { Focus.focus(:up)    }   # K
WM.on_key(0x25, [:alt]) { Focus.focus(:right) }   # L

# ⌥⇧ + H/J/K/L = 入れ替え
WM.on_key(0x04, [:alt, :shift]) { Focus.swap(:left)  }
WM.on_key(0x26, [:alt, :shift]) { Focus.swap(:down)  }
WM.on_key(0x28, [:alt, :shift]) { Focus.swap(:up)    }
WM.on_key(0x25, [:alt, :shift]) { Focus.swap(:right) }

# ⌥⌃ + H/L = 幅を −50 / +50
WM.on_key(0x04, [:alt, :ctrl]) { Focus.resize(-50, 0) }
WM.on_key(0x25, [:alt, :ctrl]) { Focus.resize(50, 0)  }

# ⌥Tab = 同じアプリのウィンドウを巡回
WM.on_key(0x30, [:alt]) { Focus.cycle_same_app }
```

## カスタマイズ

- ⌥H などが入力系アプリと衝突するなら、修飾を `[:cmd, :alt]` に変えるか
  [リーダーキー]({{ '/recipes/leader' | relative_url }})方式にする。
- `cycle_same_app` を全アプリ横断（`WM.windows` 全体を巡回）にすれば alt-tab 風になる。
  巡回対象を `select` で絞るのも自由。

## 関連

- yabai / AeroSpace の focus・warp・resize との対応は
  [yabai から]({{ '/from-yabai' | relative_url }}) / [AeroSpace から]({{ '/from-aerospace' | relative_url }})。
