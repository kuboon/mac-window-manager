---
title: 自動 BSP タイリング
parent: レシピ集
nav_order: 3
---

# 自動 BSP タイリング（yabai の `layout bsp` 相当）

今の Space の全ウィンドウを、**可視領域を再帰的に二分**して隙間なく敷き詰める。
長い辺を割っていくので yabai の自動 split と同じ形になる。`GAP` は `window_gap` 相当。

⌘⌥Return で敷き直し。`WM.on_space_changed` に繋げば Space を切り替えるたびに自動で整列する。

```ruby
{% include code/bsp.rb %}
```

## カスタマイズ

- **隙間**: `GAP` を変える。外周だけ広げたいなら `retile` で `layout` に渡す矩形を
  内側に縮める（padding 相当）。
- **並び順**: `WM.windows` の順序（前面から）で詰める。`sort_by { |w| w["app"] }` などで
  安定させたり、フォーカス窓を先頭に持ってきて「メインを大きく」もできる。
- **分割ルール**: `w >= h`（長い辺を割る）の条件や `half` の比率を変えれば
  「常に縦分割」「黄金比」なども作れる。
- **常時自動整列に近づける**: 現状ウィンドウの生成/破棄イベントは無いので、
  `on_space_changed`・キー・[CLI]({{ '/recipes/cli' | relative_url }})（`WindowManager eval 'BSP.retile'`）
  をトリガに敷き直す。

## 関連

- yabai からの乗り換え全般は [yabai から]({{ '/from-yabai' | relative_url }})（skhd 対応表つき）。
- 均等な列/行やメイン+スタックで良ければ [列・行・メイン+スタック]({{ '/recipes/tiles' | relative_url }}) の方が単純。
