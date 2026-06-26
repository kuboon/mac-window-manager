# Ruby Window Manager (Swift + ruby.wasm)

Ruby で挙動を記述・ホットリロードできる、Swift 製の macOS ウィンドウマネージャ。

既存のウィンドウマネージャを微調整するたびに Swift を再ビルドするのは面倒なので、
**ネイティブアプリに WebAssembly ランタイムを組み込み、ユーザが書いた Ruby (ruby.wasm)
からウィンドウ操作とキーイベント処理を行えるようにする**ことを狙う。
`~/.wmrc.rb` を編集してメニューバーの **Reload config** を押すだけで挙動が変わる。

> **対応 OS**: macOS 13+。ビルド・実行は macOS でのみ可能（macOS のウィンドウ/イベント API に依存）。

## 何ができるか

- macOS の全ウィンドウを列挙し、位置・サイズ・前面化・最小化を Ruby から操作
- 複数ディスプレイ情報の取得（座標は top-left に統一）
- グローバルキーイベントを Ruby のハンドラで処理（イベントの握りつぶし＝リマップ可）
- 設定（Ruby コード）のホットリロード

公開している OS API の完全な一覧は **[docs/macos-window-api.md](docs/macos-window-api.md)** を参照。

## アーキテクチャ

```
WindowManager.app (AppKit, メニューバー常駐)
├─ Native (Swift)            … AX / CGWindowList / NSScreen / NSWorkspace / CGEvent タップ
│    └─ RpcBridge            … JSON-RPC method → ネイティブ API 呼び出し
├─ RubyVM (WasmKit)          … ruby.wasm を実行。eval / キーディスパッチ
│    └─ RpcChannel           … fd 3 上の同期 JSON-RPC（Ruby ⇄ Swift）
└─ Resources
     ├─ ruby.wasm            … CRuby の WASI ビルド（要取得, 後述）
     ├─ wm.rb                … Ruby 標準ライブラリ（WM モジュール）
     └─ default.wmrc.rb      … 初回に ~/.wmrc.rb へコピーされるサンプル
```

- **Ruby → Swift**（API 呼び出し）: `WM.move(id, x, y)` 等が fd 3 へ JSON 1 行を `write` →
  Swift の WASI レイヤがそれを `RpcBridge.dispatch` に渡してメインスレッドで同期実行 →
  応答 JSON を `read` で返す。wasm 呼び出し境界の内側で同期完結する。
- **Swift → Ruby**（キーディスパッチ）: `CGEvent` タップがキーごとに
  `WM._dispatch_key(keycode, flags, down)` を `eval` し、戻り値が truthy ならイベントを consume。

座標系は AppKit(bottom-left) と CG/AX(top-left) で食い違うため、**top-left に統一**して
`Sources/WindowManager/Native/Geometry.swift` の 1 箇所だけで変換している。

## ビルドと実行

### 1. ruby.wasm の取得

サイズが大きいためリポジトリには含めていない（`.gitignore` 済み）。
[ruby/ruby.wasm](https://github.com/ruby/ruby.wasm) のリリースから **WASI 向けビルド**
（`ruby+stdlib.wasm` 等）を取得し、次へ配置する:

```
Sources/WindowManager/Resources/ruby.wasm
```

> どのビルド（raw C-API か `rb-abi-guest` コンポーネントか）を使うかで `RubyVM.eval` の
> エクスポート呼び出しが変わる。`@ruby/wasm-wasi`(JS) の `RubyVM` 実装を参照のこと。

### 2. ビルド & バンドル

```sh
make app      # swift build → WindowManager.app を組み立て、adhoc 署名
make run      # ビルドして open
make test     # ユニットテスト
```

`Developer ID` で署名する場合は `make app CODESIGN_ID="Developer ID Application: ..."`。

### 3. 権限の付与

初回起動でアクセシビリティ権限を要求する。
**システム設定 > プライバシーとセキュリティ > アクセシビリティ** で本アプリを許可し、再起動する。
ウィンドウ**タイトル**取得には **画面収録** 権限も必要（任意）。

### 4. カスタマイズ

`~/.wmrc.rb` を編集 → メニューバーの **Reload config**。再ビルド不要。
サンプル（`default.wmrc.rb`）には Cmd+Opt+←/→/↑ で左半分/右半分/最大化する例が入っている。

## 実装ステータス（正直な現状）

この環境（Linux）では macOS バイナリをビルド・実行できないため、**未検証**の箇所がある:

- ✅ **完成・レビュー可**: OS API インベントリ、ネイティブ Swift ラッパ
  (`WindowAPI`/`ScreenAPI`/`AppAPI`/`EventTap`/`Permissions`)、RPC ディスパッチ
  (`RpcBridge`/`RpcChannel`)、Ruby ライブラリ(`wm.rb`)、メニューバー UI、バンドル化。
- 🚧 **macOS 実機での確定が必要**（`RubyVM.swift` 内に明記）:
  1. WasmKit の現行版 API シグネチャ（`Engine`/`Store`/`Imports`/`Function`/`Caller`）に合わせた
     インスタンス化と、`fd_write`/`fd_read` フックの実装。
  2. 採用する ruby.wasm ビルドに応じた評価エントリポイント
     (`rb_eval_string_protect` または `rb_abi_guest_*`) の呼び出しと線形メモリ確保。

まず「ruby.wasm が WasmKit 上で起動し `puts` できる」ことを最優先で確認する（de-risk）。
動かない場合は WASI 完全対応の Wasmtime への差し替えを検討する。

## ライセンス

MIT（[LICENSE](LICENSE)）
