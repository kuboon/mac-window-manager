---
title: 内部資料
nav_order: 7
has_children: true
---

# 内部資料

`~/.wmrc.rb` を書くだけなら読む必要はない、実装者向けの調査・検証ドキュメント。

- [macOS Window API]({{ '/macos-window-api' | relative_url }}) — OS が提供するウィンドウ管理 API の
  網羅的なインベントリ（パラメタ・必要権限・Ruby への公開可否）。`WM` に API を足すときの出発点。
- [ruby.wasm スパイク]({{ '/ruby-wasm-spike' | relative_url }}) — ruby.wasm を WasmKit 上で動かすための
  検証結果（WIT component ABI・ホストシム・RPC フックの確定事実）。
