---
title: AeroSpace から
nav_order: 6
---

# AeroSpace から乗り換える

[AeroSpace](https://github.com/nikitabobko/AeroSpace) の
**標準的な設定が、このシステムでどう書けるか**の対応集。

## コピペで tiling レイアウト（AeroSpace の `layout tiles` 相当）

**この module を `~/.wmrc.rb` に貼れば、AeroSpace の tiling レイアウトが手に入る。**
AeroSpace の `layout tiles horizontal / vertical` に当たる「均等な列 / 行」と、よく使う
「メイン＋スタック」をまとめてある。キー1発で今の Space を敷き直す。さらに
**窓をドラッグして画面端で離すと半分/隅へ吸着（snap）**する（`WM.on_drag_end`）。

```ruby
{% include code/tiles.rb %}
```

`WM.windows` の順序を差し替えれば並び順、`ratio` を変えればメインの幅が変わる。
`snap_on_drop` の `edge`（端とみなす幅）や吸着先の割合を変えれば、吸着の当たり判定・
レイアウトを好みに調整できる（詳細は [tiles レシピ]({{ '/recipes/tiles' | relative_url }})）。

> 本システムは **Ruby の基盤**。ウィンドウ操作・キー入力・永続化の最小プリミティブだけを提供し、
> レイアウトの「振る舞い」は上の module のように**あなたが Ruby で書く**。

> キーコードは US 物理位置。一覧は [API リファレンス]({{ '/wmrc-guide' | relative_url }})。
> 修飾キーは `:cmd :shift :alt :ctrl`（fn は不可）。

## `~/.aerospace.toml` → `~/.wmrc.rb`

方向フォーカス / 移動 / リサイズは、レシピ集の
**[方向フォーカスと入れ替え]({{ '/recipes/focus' | relative_url }})**（`Focus` module）と
**[半分・1/4・中央]({{ '/recipes/halves' | relative_url }})**（`Halves` module）を先に貼っておくと、
`~/.aerospace.toml`（左）がそのまま移せる（右）。

| `~/.aerospace.toml` | `~/.wmrc.rb` |
|---|---|
| `alt-h = 'focus left'` | `WM.on_key(0x04, [:alt]) { Focus.focus(:left) }` |
| `alt-shift-h = 'move left'` | `WM.on_key(0x04, [:shift, :alt]) { Focus.swap(:left) }` |
| `alt-minus = 'resize smart -50'` | `WM.on_key(0x1B, [:alt]) { Focus.resize(-50, -50) }` |
| `alt-f = 'fullscreen'` | `WM.on_key(0x03, [:alt]) { Halves.maximize }` |
| `alt-1 = 'workspace 1'` | 仮想ワークスペースで対応（下記） |
| `[mode.service]` / `mode service` で入る | `WM.on_any_key` によるモード（下記） |
| CLI: `aerospace layout tiles` | CLI: `WindowManager eval 'Tiling.columns'`（[CLI 連携]({{ '/recipes/cli' | relative_url }})） |

**モード（AeroSpace の service モード相当）** は状態変数 ＋ `on_any_key` で:

```ruby
mode = nil
WM.on_any_key do |ev|
  next false unless ev[:key_down]
  if mode == :service
    case ev[:keycode]
    when 0x0F then Halves.maximize; mode = nil   # r = 例として最大化（任意の操作を割り当て）
    when 0x35 then mode = nil                    # Esc = mode main へ戻る
    else mode = nil
    end
    next true
  end
  # 注: 設定リロード（AeroSpace の reload-config）はメニュー ▸ Reload config（⌘R）か
  #     CLI の `WindowManager reload` で。
  # alt-shift-; で service モードへ（; = 0x29）。修飾ビットは WM.normalize_mods で作る。
  if ev[:keycode] == 0x29 && ev[:mods] == WM.normalize_mods([:alt, :shift])
    mode = :service; puts "-- service: r=fullscreen Esc=exit"; next true
  end
  false
end
```

（より作り込んだモードの雛形は [リーダーキー・モード]({{ '/recipes/leader' | relative_url }})。）

## 仮想ワークスペース（AeroSpace と同じ「画面外退避」方式）

AeroSpace は native Spaces を使わず、隠したいウィンドウを画面外へ退避して独自のワークスペースを
実装している。これは `WM.move` だけでできるので、**private API も SIP 緩和も無しに Ruby で再現できる**。

下は最小実装。`alt-1..3` でワークスペース切替、`alt-shift-1..3` でフォーカス窓を移動。所属と復元座標は
`WM.save`/`WM.load` で再起動をまたいで保持する。

```ruby
{% include code/workspaces.rb %}
```

注意点:

- これは「画面外に置いて隠す」擬似ワークスペース。Mission Control 上では全部同じ Space にいる
  （Dock の Spaces バーには出ない）。AeroSpace と同じ割り切り。
- 「最小化（`WM.minimize`）で隠す」方式に変えても良い。Dock にしまわれる代わりにアニメーションが入る。
- native の Spaces そのものを操作したい（`alt-1` で OS の Space を切り替えたい）場合は private API が
  必要で現状未対応。違いは [API リファレンス]({{ '/wmrc-guide' | relative_url }}) と
  [yabai から]({{ '/from-yabai' | relative_url }}) を参照。
- ワークスペース数の増やし方などは [仮想ワークスペースのレシピ]({{ '/recipes/workspaces' | relative_url }})。

## まだ 1:1 にならないもの（正直な現状）

- **自動タイリング（ツリー管理）**: 常駐してツリーを保持し続ける「完成品の自動タイル」は無い。
  ただし冒頭の Tiling module（や [BSP]({{ '/recipes/bsp' | relative_url }})）で、キー1発や
  Space 切替フックから同等のレイアウトに敷き直せる。
- **native macOS Spaces**: 上記の「画面外退避」で体験は再現できるが、OS の Space そのものの切替・
  ウィンドウ移動は private API が必要なため未対応。
- **float / managed の区別**: すべて「手動で管理」なので float の概念は無い。「動かしたくない窓は
  そのキーで触らない」だけ。

---

> このページは「よくある設定」を中心にした出発点です。あなたの AeroSpace 設定で
> 「これはどう書く？」があれば Issue へ。[レシピ]({{ '/recipes/' | relative_url }})を増やしていきます。
