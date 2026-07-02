---
title: 列・行・メイン+スタック
parent: レシピ集
nav_order: 4
---

# 列・行・メイン+スタック（AeroSpace の `layout tiles` 相当）

定番のタイルレイアウト 3 種をワンキーで:

- **均等な列**（⌘⌥H）… AeroSpace の `tiles horizontal`
- **均等な行**（⌘⌥V）… `tiles vertical`
- **メイン+スタック**（⌘⌥Return）… 左に主役 1 枚、右に残りを縦積み

さらに**ドラッグして画面端で離すと半分/隅へ吸着**（`snap_on_drop`）も入っている。

```ruby
{% include code/tiles.rb %}
```

## カスタマイズ

- **メインの幅**: `main_stack` の `ratio: 0.6` を変える。
- **並び順**: `WM.windows`（前面順）を並べ替えて渡せば順序が変わる。
  `Tiling.main_stack(WM.windows.sort_by { |w| w["app"] })` のように呼んでもいい。
- **隙間**: `GAP`。
- **吸着の当たり判定**: `snap_on_drop` の `edge = 0.15`（画面の 15%）を調整。
  px 固定で判定したい場合は [ドラッグで吸着]({{ '/recipes/snap' | relative_url }}) 版を参照。

## 関連

- AeroSpace からの乗り換え全般は [AeroSpace から]({{ '/from-aerospace' | relative_url }})（toml 対応表・mode の移植つき）。
- 隙間なく全部敷き詰めたいなら [自動 BSP タイリング]({{ '/recipes/bsp' | relative_url }})。
