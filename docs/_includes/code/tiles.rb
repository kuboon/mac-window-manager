module Tiling
  GAP = 8   # 窓どうし・画面端の隙間

  class << self
    # 均等な列（tiles horizontal）: 窓を左から右へ縦に割って並べる。
    def columns(wins = WM.windows, screen: WM.screens.first)
      grid(wins, screen, cols: wins.size, rows: 1)
    end

    # 均等な行（tiles vertical）: 窓を上から下へ横に割って並べる。
    def rows(wins = WM.windows, screen: WM.screens.first)
      grid(wins, screen, cols: 1, rows: wins.size)
    end

    # メイン＋スタック: 左に主役 1 枚、右に残りを縦積み。
    def main_stack(wins = WM.windows, screen: WM.screens.first, ratio: 0.6)
      return unless screen && !wins.empty?
      main, *rest = wins
      place(main, screen, 0.0, 0.0, rest.empty? ? 1.0 : ratio, 1.0)
      rest.each_with_index do |w, i|
        place(w, screen, ratio, i.to_f / rest.size, 1.0 - ratio, 1.0 / rest.size)
      end
    end

    # ドラッグ&ドロップした窓を、カーソルが居る画面端/隅へ吸着（Rectangle 風の snap）。
    # ev = { window:, x:, y: }（x,y は top-left グローバルなドロップ位置）。
    # 端に寄っていないドロップは何もしない（＝通常のドラッグ移動を邪魔しない）。
    def snap_on_drop(ev)
      screen = screen_at(ev[:x], ev[:y]) or return
      fx = ((ev[:x] - screen["visible_x"]) / screen["visible_w"]).clamp(0.0, 1.0)
      fy = ((ev[:y] - screen["visible_y"]) / screen["visible_h"]).clamp(0.0, 1.0)

      edge = 0.15   # この割合ぶん端に入ったら「その端」とみなす
      left   = fx < edge;      right  = fx > 1 - edge
      top    = fy < edge;      bottom = fy > 1 - edge
      return unless left || right || top || bottom   # 中央付近ならそのまま

      # 左右→左右半分、上下→上下半分、隅（左右かつ上下）→1/4。
      fx0, fw = left ? [0.0, 0.5] : right  ? [0.5, 0.5] : [0.0, 1.0]
      fy0, fh = top  ? [0.0, 0.5] : bottom ? [0.5, 0.5] : [0.0, 1.0]
      place({ "id" => ev[:window] }, screen, fx0, fy0, fw, fh)
    end

    private

    # 可視領域を cols×rows のグリッドに割って詰める。
    def grid(wins, screen, cols:, rows:)
      return unless screen && !wins.empty?
      wins.each_with_index do |w, i|
        place(w, screen, (i % cols).to_f / cols, (i / cols).to_f / rows,
              1.0 / cols, 1.0 / rows)
      end
    end

    # 可視領域に対する割合 (fx,fy,fw,fh) で 1 枚を配置（GAP 込み）。
    def place(w, screen, fx, fy, fw, fh)
      x = screen["visible_x"] + screen["visible_w"] * fx + GAP
      y = screen["visible_y"] + screen["visible_h"] * fy + GAP
      ww = screen["visible_w"] * fw - 2 * GAP
      hh = screen["visible_h"] * fh - 2 * GAP
      WM.move(w["id"], x, y); WM.resize(w["id"], ww, hh)
    end

    # カーソル (x,y) を含むスクリーンを返す（マルチモニタ対応。無ければ先頭）。
    def screen_at(x, y)
      WM.screens.find { |s|
        x >= s["visible_x"] && x < s["visible_x"] + s["visible_w"] &&
        y >= s["visible_y"] && y < s["visible_y"] + s["visible_h"]
      } || WM.screens.first
    end
  end
end

# ⌘⌥H で均等な列、⌘⌥V で均等な行、⌘⌥Return でメイン＋スタック
WM.on_key(0x04, [:cmd, :alt]) { Tiling.columns }     # H
WM.on_key(0x09, [:cmd, :alt]) { Tiling.rows }        # V
WM.on_key(0x24, [:cmd, :alt]) { Tiling.main_stack }  # Return

# 窓をドラッグして画面端/隅で離すと、その半分/1/4 へ吸着（snap）。
WM.on_drag_end { |ev| Tiling.snap_on_drop(ev) }

# Space 切替のたびに自動で敷き直したい場合:
WM.on_space_changed { Tiling.columns }
