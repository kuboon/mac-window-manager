---
title: リーダーキー・モード
parent: レシピ集
nav_order: 9
---

# リーダーキー・モード（F1 → 1 キーで操作）

修飾キーの同時押しではなく、**F1 を押してから 1 キー**で操作するモーダル方式
（vim や AeroSpace の mode に相当）。ショートカットの占有が F1 の 1 個で済むので、
アプリのキーバインドと衝突しない。

- **F1 → T** … 左半分 / **F1 → Y** … 右半分 / **F1 → F** … 最大化
- モード中のキーはすべて consume される（誤爆してもアプリに漏れない）
- 割り当ての無いキーや Esc で抜ける

```ruby
module Leader
  KEY = 0x7A   # モードに入るキー（F1、修飾なし）

  # モード中に押すキー => 実行する処理。自由に増やせる。
  BINDINGS = {
    0x11 => -> { tile_focused(0.0, 0.0, 0.5, 1.0) },   # T = 左半分
    0x10 => -> { tile_focused(0.5, 0.0, 0.5, 1.0) },   # Y = 右半分
    0x03 => -> { tile_focused(0.0, 0.0, 1.0, 1.0) },   # F = 最大化
    # 0x08 => -> { BSP.retile },                       # C = BSP 敷き直し（BSP レシピ併用時）
  }

  def self.tile_focused(fx, fy, fw, fh)
    id = WM.focused_window
    WM.tile(id, fx, fy, fw, fh) if id
  end
end

leader_active = false
WM.on_any_key do |ev|
  next false unless ev[:key_down]

  if leader_active
    leader_active = false                      # 1 打で抜ける（連打モードにするならここを工夫）
    Leader::BINDINGS[ev[:keycode]]&.call       # 未割り当てキーは何もせず抜けるだけ
    next true                                  # モード中の 1 打は必ず consume
  end

  if ev[:keycode] == Leader::KEY && ev[:mods] == 0
    leader_active = true
    puts "-- leader: T=左 Y=右 F=最大化（他キーでキャンセル）"
    next true
  end

  false                                        # それ以外は素通し
end
```

## カスタマイズ

- **操作を増やす**: `BINDINGS` に `keycode => -> { ... }` を足すだけ
  （キーコードは [表]({{ '/wmrc-guide' | relative_url }})）。
  他レシピの module を呼べば「F1 → C で BSP」「F1 → 1 でワークスペース 1」なども一瞬。
- **連打できるモードにする**: `leader_active = false` を BINDINGS ヒット時には実行しない
  ようにして、Esc（0x35）でだけ抜ける。
- **サブモード**: `leader_active` を `:leader` / `:leader_g` のような値にして分岐を増やす。
- リーダーキーを F1 以外に: `KEY` を変える。修飾つき（例 ⌥Space）にするなら
  `ev[:mods] == WM.normalize_mods([:alt])` で判定する。

## 関連

- `WM.on_any_key` の仕様（keyUp でも呼ばれる・on_key より先に評価）は
  [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2.7。
- 自動タイムアウトは無い（ランタイムにタイマーが無いため）。抜け道は「実行」「未割り当てキー」。
