---
title: yabai から
nav_order: 5
---

# yabai から乗り換える

[yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/koekeishiya/skhd) の
**標準的な設定が、このシステムでどう書けるか**の対応集。

## コピペで BSP タイリング（yabai の `layout bsp` 相当）

**この module を `~/.wmrc.rb` に貼れば、yabai の自動 BSP タイリングが手に入る。**
可視領域を再帰的に二分し、長い辺を割る（yabai の自動 split と同じ挙動）。`window_gap` も付く。

```ruby
{% include code/bsp.rb %}
```

`GAP` を変えれば `window_gap`、`layout` に渡す矩形を内側へ縮めれば padding になる。
`WM.windows` の順序を差し替えれば「マスターを大きく」等の変種も Ruby で自由に組める
（調整のバリエーションは [BSP レシピ]({{ '/recipes/bsp' | relative_url }})）。

> 本システムは **Ruby の基盤**。ウィンドウ操作・キー入力・永続化の最小プリミティブだけを提供し、
> レイアウトの「振る舞い」は上の module のように**あなたが Ruby で書く**。キーバインド＋ウィンドウ操作
> （focus / warp / resize / fullscreen / tile）はそのまま移植でき、BSP も上でそのまま再現できる。
> Spaces だけは private API が要るので現状 1:1 にはならない（後述）。

> キーコードは US 物理位置。一覧は [API リファレンス]({{ '/wmrc-guide' | relative_url }})。
> 修飾キーは `:cmd :shift :alt :ctrl`（fn は不可）。

## `~/.skhdrc` → `~/.wmrc.rb`

方向フォーカス / warp / リサイズは、レシピ集の
**[方向フォーカスと入れ替え]({{ '/recipes/focus' | relative_url }})**（`Focus` module）と
**[半分・1/4・中央]({{ '/recipes/halves' | relative_url }})**（`Halves` module）を先に貼っておくと、
`~/.skhdrc` の典型例（左）がそのまま 1 行ずつ移せる（右）。

| `~/.skhdrc`（yabai） | `~/.wmrc.rb` |
|---|---|
| `alt - h : yabai -m window --focus west` | `WM.on_key(0x04, [:alt]) { Focus.focus(:left) }` |
| `alt - l : yabai -m window --focus east` | `WM.on_key(0x25, [:alt]) { Focus.focus(:right) }` |
| `alt - j : yabai -m window --focus south` | `WM.on_key(0x26, [:alt]) { Focus.focus(:down) }` |
| `alt - k : yabai -m window --focus north` | `WM.on_key(0x28, [:alt]) { Focus.focus(:up) }` |
| `shift + alt - h : yabai -m window --warp west` | `WM.on_key(0x04, [:shift, :alt]) { Focus.swap(:left) }` |
| `ctrl + alt - h : yabai -m window --resize left:-50:0` | `WM.on_key(0x04, [:ctrl, :alt]) { Focus.resize(-50, 0) }` |
| `alt - f : yabai -m window --toggle zoom-fullscreen` | `WM.on_key(0x03, [:alt]) { Halves.maximize }` |
| `alt - 1 : yabai -m space --focus 1` | ⏳ native Spaces 未対応（後述）。[仮想ワークスペース]({{ '/recipes/workspaces' | relative_url }})で代替可 |

（H=0x04, J=0x26, K=0x28, L=0x25, F=0x03。`yabairc` の gaps / padding は BSP module の `GAP` で。）

## `yabai -m ...` を CLI から

yabai の CLI 操作（`yabai -m window --focus west` など）に相当するものとして、
定義済みの module を**そのままシェルから呼べる**:

```sh
WindowManager eval 'Focus.focus(:left)'
WindowManager eval 'BSP.retile'
```

詳細は [CLI 連携]({{ '/recipes/cli' | relative_url }})。

## まだ 1:1 にならないもの（正直な現状）

- **Spaces（Mission Control の仮想デスクトップ）切替**: macOS の Spaces 操作は private な
  SkyLight/CGS API が必要で、yabai も scripting addition（SIP 一部無効化）でこれを叩いている。
  本システムは現状 RPC 未提供（将来 `WM.space_focus` 等を足せば対応可能）。
  「Space が**切り替わった**こと」の検出は `WM.on_space_changed` で可能（public 通知ベース）。
  Spaces を**使わず**ワークスペースを再現する手は
  [仮想ワークスペース]({{ '/recipes/workspaces' | relative_url }})（`move` で画面外退避するだけ。
  private API 不要）。
- **自動 BSP タイリング（ツリー管理）**: 常駐してツリーを保持し続ける「完成品の自動タイル」は無い。
  ただし冒頭の BSP module で、キー1発（や Space 切替フック）で yabai と同じ BSP レイアウトに
  敷き直せる。
- **float / managed の区別**: すべて「手動で管理」なので float の概念は無い。「動かしたくない窓は
  そのキーで触らない」だけ。

---

> このページは「よくある設定」を中心にした出発点です。あなたの yabai 設定で
> 「これはどう書く？」があれば Issue へ。[レシピ]({{ '/recipes/' | relative_url }})を増やしていきます。
