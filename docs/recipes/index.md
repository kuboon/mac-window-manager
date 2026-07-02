---
title: レシピ集
nav_order: 3
has_children: true
---

# レシピ集 — コピペで使える設定モジュール

各ページの module を **`~/.wmrc.rb` に貼って Reload するだけ**で、その機能が手に入る。
どれも独立しているので、欲しいものだけ組み合わせられる。貼ったあとはただの Ruby なので、
キーもレイアウトも 1 行単位で自分好みに変えていける。

| レシピ | できること | 似ているツール |
|---|---|---|
| [半分・1/4・中央]({{ '/recipes/halves' | relative_url }}) | ⌘⌥+矢印で半分/最大化、連打で 1/2→1/3→2/3 サイクル | Rectangle, Magnet |
| [ドラッグで吸着]({{ '/recipes/snap' | relative_url }}) | 窓を画面端へドラッグして離すと半分/1/4 に吸着 | Windows の Aero Snap |
| [自動 BSP タイリング]({{ '/recipes/bsp' | relative_url }}) | 全ウィンドウを再帰二分割で隙間なく敷き詰め | yabai の `layout bsp` |
| [列・行・メイン+スタック]({{ '/recipes/tiles' | relative_url }}) | 均等な列/行、メイン+サブの定番レイアウト | AeroSpace の `layout tiles` |
| [仮想ワークスペース]({{ '/recipes/workspaces' | relative_url }}) | alt-1/2/3 でワークスペース切替（native Spaces 不使用） | AeroSpace |
| [方向フォーカスと入れ替え]({{ '/recipes/focus' | relative_url }}) | ⌥HJKL で隣の窓へフォーカス移動・位置交換・巡回 | yabai + skhd |
| [マルチディスプレイ]({{ '/recipes/displays' | relative_url }}) | 窓を次/前のディスプレイへ投げる（相対位置を保持） | Rectangle の Next Display |
| [レイアウト保存と復元]({{ '/recipes/layouts' | relative_url }}) | 全窓の配置をディスプレイ構成ごとに保存、再起動後に復元 | Stay, Workspacer |
| [リーダーキー・モード]({{ '/recipes/leader' | relative_url }}) | F1 → 1 キーで操作するモーダル操作 | vim, AeroSpace の mode |
| [アプリのホットキー]({{ '/recipes/apps' | relative_url }}) | 1 キーでアプリへフォーカス / 表示・非表示トグル | ドロップダウンターミナル |
| [CLI 連携]({{ '/recipes/cli' | relative_url }}) | ターミナル / Raycast / スクリプトから module を呼ぶ | yabai -m |

## 使い方の基本

1. レシピの code block を丸ごとコピーして `~/.wmrc.rb` の末尾に貼る。
2. メニューバー `▦` ▸ **Reload config**（または `WindowManager reload`）。
3. キーが他のレシピや既存ショートカットと被ったら、`WM.on_key(0x??, [...])` の
   キーコードを変える（[キーコード表]({{ '/wmrc-guide' | relative_url }})）。

> 各レシピは `WM` の公開 API（[API リファレンス]({{ '/wmrc-guide' | relative_url }})）だけで
> 書かれた素の Ruby。動きを変えたければ、そのまま編集すればいい。
