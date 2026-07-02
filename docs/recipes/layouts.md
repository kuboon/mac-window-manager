---
title: レイアウト保存と復元
parent: レシピ集
nav_order: 8
---

# レイアウト保存と復元

**⌘⌥S で全ウィンドウの配置を保存、⌘⌥R で復元。**

保存は「ディスプレイ構成（画面名の組）」をキーに行うので、**ノート単体とドック接続時で
別々のレイアウト**を持てる。`WM.save` による永続化なので再起動をまたいで残る。

```ruby
module Layouts
  class << self
    # 現在のディスプレイ構成を表すキー
    def signature
      WM.screens.map { |s| s["name"] }.sort.join(" | ")
    end

    def store(slot = "default")
      snap = WM.windows.map { |w| w.slice("app", "title", "x", "y", "w", "h") }
      WM.save("layout:#{slot}:#{signature}", snap)
      puts "[layouts] saved #{snap.size} windows (#{slot} @ #{signature})"
    end

    # CGWindowID は再起動で変わるため app+title で照合する。
    # title が変わっていた窓は「同じアプリでまだ使っていない窓」で代替する。
    def restore(slot = "default")
      saved = WM.load("layout:#{slot}:#{signature}") || []
      wins = WM.windows
      used = []
      saved.each do |s|
        win = wins.find { |w|
                !used.include?(w["id"]) && w["app"] == s["app"] && w["title"] == s["title"] } ||
              wins.find { |w| !used.include?(w["id"]) && w["app"] == s["app"] }
        next unless win
        used << win["id"]
        WM.move(win["id"], s["x"], s["y"])
        WM.resize(win["id"], s["w"], s["h"])
      end
      puts "[layouts] restored #{used.size}/#{saved.size} (#{slot} @ #{signature})"
    end
  end
end

WM.on_key(0x01, [:cmd, :alt]) { Layouts.store }     # ⌘⌥S 保存
WM.on_key(0x0F, [:cmd, :alt]) { Layouts.restore }   # ⌘⌥R 復元

# ディスプレイ抜き差しで、その構成の保存レイアウトを自動適用したい場合はコメントを外す。
# （AppKit は 1 回の抜き差しで複数回通知するが、restore は冪等なので問題ない）
# WM.on_screens_changed { Layouts.restore }
```

## 使い方のコツ

- **再起動後の流れ**: ログイン項目で WindowManager を起動 → 対象アプリの窓が揃ってから
  **⌘⌥R を 1 回**。`CGWindowID` は再起動で変わるため id では復元できず、app+title で照合する。
- **複数スロット**: `Layouts.store("coding")` / `Layouts.restore("coding")` のように
  スロット名を渡せば、用途別レイアウトを何個でも持てる（キーを足すか
  [CLI]({{ '/recipes/cli' | relative_url }}) から
  `WindowManager eval 'Layouts.restore("coding")'` で呼ぶ）。

## 関連

- 永続ストレージ `WM.save`/`WM.load` の仕様は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2.6。
