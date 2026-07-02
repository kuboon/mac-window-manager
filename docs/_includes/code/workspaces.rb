module WS
  PARK = [-100000, -100000]   # 画面外の退避先
  NAMES = %w[1 2 3]

  class << self
    def current = WM.load("ws:current") || "1"

    def current=(n)
      WM.save("ws:current", n)
    end

    # window_id => 所属ワークスペース名
    def owner = WM.load("ws:owner") || {}

    def owner=(h)
      WM.save("ws:owner", h)
    end

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

WS::NAMES.each_with_index do |n, i|
  WM.on_key(0x12 + i, [:alt])         { WS.switch(n) }        # alt-1/2/3
  WM.on_key(0x12 + i, [:alt, :shift]) { WS.move_focused(n) }  # alt-shift-1/2/3
end
# 0x12=1, 0x13=2, 0x14=3（数字キーの並び）
