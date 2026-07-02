---
title: 仮想ワークスペース
parent: レシピ集
nav_order: 5
---

# 仮想ワークスペース（画面外退避方式）

**alt-1/2/3 でワークスペース切替、alt-shift-1/2/3 でフォーカス窓を移動。**

AeroSpace と同じ発想で、native な macOS Spaces を使わず「他のワークスペースの窓を
画面外へ退避する」ことでワークスペースを実現する。`WM.move` だけでできるので
**private API も SIP 緩和も不要**。所属と復元座標は `WM.save`/`WM.load` で永続化され、
再起動をまたいで保持される。

```ruby
{% include code/workspaces.rb %}
```

## カスタマイズ

- **ワークスペース数**: `NAMES = %w[1 2 3 4 5]` にしてキー登録も増やす（0x15=4, 0x17=5）。
- **切替時にレイアウトも当てたい**: `switch` の最後で
  [BSP]({{ '/recipes/bsp' | relative_url }}) や [tiles]({{ '/recipes/tiles' | relative_url }}) の
  敷き直しを呼ぶ。
- **隠し方を最小化に変える**: `WM.move(id, *PARK)` を `WM.minimize(id)` に、
  復元を `WM.minimize(id, false)` にすると Dock にしまう方式になる
  （アニメーションが入る代わりに Mission Control が散らからない）。

## 制約（知っておくこと）

- Mission Control 上では全窓が同じ Space にいる（Dock の Spaces バーには出ない）。
  AeroSpace と同じ割り切り。
- native の Spaces そのものの操作（OS の Space 切替・窓の Space 間移動）は private API が
  必要で未対応。詳細は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2.9。

## 関連

- [AeroSpace から]({{ '/from-aerospace' | relative_url }}) — 乗り換え全般の対応表。
