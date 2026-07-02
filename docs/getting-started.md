---
title: はじめる
nav_order: 2
---

# はじめる

インストールから最初のカスタマイズまで。5 分で終わる。

## 1. 入手して起動

[GitHub Releases](https://github.com/kuboon/mac-window-manager/releases) から
`WindowManager.app.zip` を取得して展開する。adhoc 署名（未公証）なので初回は
**右クリック → 開く**、または:

```sh
xattr -dr com.apple.quarantine WindowManager.app
```

起動するとメニューバーに `▦` が出る（Dock には出ない）。

## 2. 権限を付与

| 権限 | 必須? | 用途 |
|---|---|---|
| **アクセシビリティ** | 必須 | ウィンドウの移動・リサイズ・キーイベントの取得 |
| **画面収録** | 任意 | ウィンドウ**タイトル**の取得（未許可だと `title` が空文字になる） |

初回起動時にアクセシビリティ権限を要求される。
**システム設定 ▸ プライバシーとセキュリティ ▸ アクセシビリティ** で許可して、アプリを再起動する。

## 3. 設定ファイル `~/.wmrc.rb`

初回起動時にサンプル設定が `~/.wmrc.rb` にコピーされる。この時点で
**⌘⌥← / ⌘⌥→ / ⌘⌥↑**（左半分 / 右半分 / 最大化）と、**⌘⌥S / ⌘⌥R**
（レイアウト保存 / 復元）が使える。

編集して反映するには:

- メニューバー `▦` ▸ **Reload config**（⌘R）、または
- CLI から `WindowManager reload`（[CLI 連携]({{ '/recipes/cli' | relative_url }})）

Swift の再ビルドは不要。リロードは Ruby VM ごと作り直すので、前回の状態を持ち越さず
ゼロから読み直される。

## 4. カスタマイズする

**[レシピ集]({{ '/recipes/' | relative_url }}) から欲しい module をコピペする**のが早い。
半分/1/4 タイル、ドラッグで吸着、BSP 自動整列、仮想ワークスペース、リーダーキー…が
貼るだけで手に入る。

自分で書くときは [API リファレンス]({{ '/wmrc-guide' | relative_url }}) を参照。
最小の形はこれだけ:

```ruby
WM.on_key(keycode, [modifiers]) do
  # ここに Ruby で処理を書く
end
```

## 5. うまく動かないとき

- **`puts` / エラー出力を見る**: Finder からではなくターミナルから起動すると標準出力が見える:
  ```sh
  ./WindowManager.app/Contents/MacOS/WindowManager
  ```
- **ウィンドウが動かない**: アクセシビリティ権限を確認。一部アプリ（フルスクリーン中など)は
  AX 操作を受け付けない。
- **タイトルが空**: 画面収録権限が未許可。
- そのほかは [API リファレンスの「落とし穴・デバッグ」]({{ '/wmrc-guide' | relative_url }}) へ。
