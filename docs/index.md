---
title: ホーム
nav_order: 1
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
  # マッチしたキーはデフォルトで consume される（他アプリへ渡さない）。
  # 素通りさせたいときだけブロックで `false` を返す。
end
```

## どこから読むか

| 読みたいこと | ページ |
|---|---|
| インストールして動かすまで | [はじめる]({{ '/getting-started' | relative_url }}) |
| **コピペで使える設定モジュール集**（半分タイル・BSP・ワークスペース・snap…） | [レシピ集]({{ '/recipes/' | relative_url }}) |
| `WM` の全 API・キーコード表・落とし穴 | [API リファレンス]({{ '/wmrc-guide' | relative_url }}) |
| yabai / AeroSpace の設定をどう移すか | [yabai から]({{ '/from-yabai' | relative_url }}) ・ [AeroSpace から]({{ '/from-aerospace' | relative_url }}) |
| ターミナル / Raycast から操作したい | [CLI 連携]({{ '/recipes/cli' | relative_url }}) |

## 設計思想

- **ポリシーは Ruby に置く**。フレームワーク（Swift）はウィンドウ操作・キー入力・永続化の
  **最小プリミティブ**だけを提供し、「どう振る舞うか」は全部あなたの `~/.wmrc.rb`（Ruby）で書く。
  だから設定がオプション地獄にならず、好きなだけ作り込める。
- とはいえゼロから書く必要はない。[レシピ集]({{ '/recipes/' | relative_url }})の module を
  コピペすれば、Rectangle 風の半分タイルも yabai 風の BSP も AeroSpace 風のワークスペースも
  すぐ手に入る。そこから 1 行ずつ自分好みに変えていける。

## できること / まだ無いもの

| 区分 | 状態 |
|---|---|
| ウィンドウの move / resize / raise / minimize、tile（割合配置） | ✅ |
| アプリの前面化 / 非表示、一覧、画面一覧、フォーカス取得 | ✅ |
| キーのリマップ＋consume、モード/リーダーキー | ✅（Ruby で） |
| ドラッグで snap（端へ吸着）— `WM.on_drag_end` | ✅（Ruby で） |
| ディスプレイ抜き差しイベント、Space 切替イベント、再起動をまたぐ永続保存 | ✅ |
| CLI から定義済み func/module を呼ぶ・設定リロード（`WindowManager eval … / reload`） | ✅ |
| 自動 BSP タイリング（ツリー管理） | ⏳ 常駐機能としては未提供（[BSP レシピ]({{ '/recipes/bsp' | relative_url }})でキー1発の敷き直しは可能） |
| native Spaces の操作（切替先 Space の特定 / 別 Space の窓列挙 / 窓を別 Space へ移動） | ⏳ 未提供（private SkyLight が必要。ワークスペース体験は[画面外退避]({{ '/recipes/workspaces' | relative_url }})で Ruby 再現可） |
