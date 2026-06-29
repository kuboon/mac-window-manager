---
title: ホーム
nav_order: 0
---

# Ruby Window Manager

Ruby (ruby.wasm) で挙動を**記述・ホットリロード**できる Swift 製 macOS ウィンドウマネージャ。
キー操作もウィンドウ配置も `~/.wmrc.rb` を編集して、メニューの **Reload config** を押すだけで
反映される（Swift 再ビルド不要）。

```ruby
# ~/.wmrc.rb の例: ⌘⌥← でフォーカス中ウィンドウを左半分へ
WM.on_key(0x7B, [:cmd, :alt]) do
  id = WM.focused_window
  WM.tile(id, 0.0, 0.0, 0.5, 1.0) if id
  true   # このキーを consume（他アプリへ渡さない）
end
```

## はじめに

- **入手 / 起動**: [GitHub Releases](https://github.com/kuboon/mac-window-manager/releases) から
  `WindowManager.app.zip` を取得（adhoc 署名 / 未公証 → 初回は右クリック→開く、または
  `xattr -dr com.apple.quarantine WindowManager.app`）。アクセシビリティ権限を付与して起動。
- **設定を書く**: [API リファレンス]({{ '/wmrc-guide' | relative_url }}) に `WM` の全 API・修飾キー・
  キーコード表・レシピ・落とし穴がまとまっている。これ 1 枚で `~/.wmrc.rb` が書ける。
- **乗り換え**: [yabai から]({{ '/from-yabai' | relative_url }}) / [AeroSpace から]({{ '/from-aerospace' | relative_url }})
  — 既存の tiling WM の設定がこのシステムでどう書けるかの対応表。

## 設計思想

- **ポリシーは Ruby に置く**。フレームワーク（Swift）はウィンドウ操作・キー入力・永続化の
  **最小プリミティブ**だけを提供し、「どう振る舞うか」は全部あなたの `~/.wmrc.rb`（Ruby）で書く。
  だから設定がオプション地獄にならず、好きなだけ作り込める。
- 例: モード/リーダーキー（F1 → t で tiling…）は `WM.on_any_key` という生キーフック 1 個の上に、
  状態変数を置くだけで自由に実装できる（[レシピ]({{ '/wmrc-guide' | relative_url }})）。

## できること / まだ無いもの

| 区分 | 状態 |
|---|---|
| ウィンドウの move / resize / raise / minimize、tile（割合配置） | ✅ |
| アプリの前面化 / 非表示、一覧、画面一覧、フォーカス取得 | ✅ |
| キーのリマップ＋consume、モード/リーダーキー | ✅（Ruby で） |
| ドラッグで snap（端へ吸着）— `WM.on_drag_end` | ✅（Ruby で） |
| ディスプレイ抜き差しイベント、再起動をまたぐ永続保存 | ✅ |
| 自動 BSP タイリング（ツリー管理）、Spaces/ワークスペース切替 | ⏳ 未提供（Ruby でレイアウトを組むことは可能。Spaces は新プリミティブが必要） |
