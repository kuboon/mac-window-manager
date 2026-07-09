---
title: 最小化ウィンドウ
parent: レシピ集
nav_order: 12
---

# 最小化ウィンドウ（しまう・全部戻す）

- **⌘⌥M** … フォーカス窓を最小化
- **⌘⌥⇧M** … 最小化中の窓を**すべて復元**
- **⌘⌥⌃M** … 最小化中の窓を **1 枚だけ**復元（新しくしまった順ではなく列挙順）

最小化した窓は `WM.windows`（オンスクリーン列挙）から消えるため、復元には
**`WM.all_windows`**（最小化・非表示の窓も含む全列挙、`minimized` フラグ付き）を使う。

```ruby
module Minimized
  class << self
    # フォーカス窓を最小化
    def focused
      id = WM.focused_window
      WM.minimize(id) if id
    end

    # 最小化中の窓を列挙（WM.windows には出ないので all_windows で探す）
    def list
      WM.all_windows.select { |w| w["minimized"] }
    end

    # すべて復元
    def restore_all
      list.each { |w| WM.minimize(w["id"], false) }
    end

    # 1 枚だけ復元して前面へ
    def restore_one
      w = list.first or return
      WM.minimize(w["id"], false)
      WM.activate(w["pid"])
      WM.raise_window(w["id"])
    end
  end
end

WM.on_key(0x2E, [:cmd, :alt])          { Minimized.focused }      # ⌘⌥M
WM.on_key(0x2E, [:cmd, :alt, :shift])  { Minimized.restore_all }  # ⌘⌥⇧M
WM.on_key(0x2E, [:cmd, :alt, :ctrl])   { Minimized.restore_one }  # ⌘⌥⌃M
```

## 知っておくこと

- `WM.all_windows` は各アプリの AX 状態を照合するため `WM.windows` より重い。
  キー1発・CLI で呼ぶぶんには問題ないが、毎キー入力のような高頻度では使わない。
- `WM.all_windows` の状態判定: `on_screen: true` = 見えている / `minimized: true` = 最小化中 /
  どちらも false = 非表示アプリ（`WM.hide_app` や ⌘H）か別 Space の窓。
- macOS 標準の ⌘⌥M（アプリの全窓を最小化）はこの ⌘⌥M が consume して置き換える。
  標準動作を残したいならキーコードを変える。

## 応用例

特定アプリの最小化窓だけ戻す（アプリが分かっているなら、全列挙より
プリミティブ `WM.minimized_ids(pid)` を直接使う方が軽い）:

```ruby
def restore_app(bundle_id)
  app = WM.apps.find { |a| a["bundle_id"] == bundle_id } or return
  WM.minimized_ids(app["pid"]).each { |id| WM.minimize(id, false) }
end
```

CLI から様子を見る（[CLI 連携]({{ '/recipes/cli' | relative_url }})）:

```sh
WindowManager eval 'Minimized.list.map { |w| w["app"] }'
WindowManager eval 'Minimized.restore_all'
```

## 関連

- `WM.all_windows` / `WM.minimize` の仕様は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2。
