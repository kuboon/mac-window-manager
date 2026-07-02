---
title: CLI 連携
parent: レシピ集
nav_order: 11
---

# CLI 連携（ターミナル / Raycast / スクリプトから呼ぶ)

動作中のアプリへ、**ターミナルからコマンドを送れる**。`~/.wmrc.rb` で定義した
func / module をそのまま呼べるので、キーバインドを増やさなくても
Raycast・Alfred・シェルスクリプト・cron から任意の操作を実行できる。

```sh
# ~/.wmrc.rb の定義済み module を呼ぶ（結果は inspect 表示）
WindowManager eval 'Tiling.columns'
WindowManager eval 'WM.windows.size'          # => 3
WindowManager eval 'Layouts.restore("coding")'

# ~/.wmrc.rb を再読み込み（メニューの Reload config と同じ）
WindowManager reload
```

`eval` は `--eval` / `-e` でも可。実体は `.app` の中にあるので、エイリアスを推奨:

```sh
# ~/.zshrc など
alias wmrc="$HOME/Applications/WindowManager.app/Contents/MacOS/WindowManager"

wmrc eval 'BSP.retile'    # => nil
wmrc reload               # => reloaded ~/.wmrc.rb
```

## しくみと性質

- アプリが起動中に開くローカルの Unix domain socket（`/tmp/wmrc-$USER.sock`、
  所有ユーザのみ `0600`）へリクエストを送る。ネットワークには出ない。
- eval は**アプリ内の唯一の Ruby VM 上**・**キーハンドラと同じメインスレッド**で
  直列実行される。`~/.wmrc.rb` の定義・状態（module のインスタンス変数、
  `WM.save`/`WM.load` の値）にそのままアクセスできる。
- アプリが起動していなければ終了コード 1 で `error: ...` を返す。
  結果が `error:` で始まるときも終了コード 1（スクリプトから判定できる）。

## Raycast Script Command の例

`~/.wmrc.rb` に module（例: [tiles レシピ]({{ '/recipes/tiles' | relative_url }})）を入れておき、
Raycast のスクリプトから呼ぶ:

```bash
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Tile: Main + Stack
# @raycast.mode silent

~/Applications/WindowManager.app/Contents/MacOS/WindowManager eval 'Tiling.main_stack'
```

同じ要領で「レイアウト復元」「ワークスペース切替」など、レシピの公開メソッドは
何でもコマンド化できる。

## デバッグにも便利

```sh
wmrc eval 'WM.windows'                          # 窓一覧をその場で確認
wmrc eval 'WM.screens.map { |s| s["name"] }'    # ディスプレイ名
wmrc eval 'WM.handlers.size'                    # 登録済みキーハンドラ数
```

> `eval` は任意の Ruby を実行する。ソケットは所有ユーザしか書けないが、
> 共有マシンでは念のため意識しておくこと。
