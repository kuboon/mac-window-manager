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
