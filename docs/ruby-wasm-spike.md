# ruby.wasm × WasmKit 検証結果（de-risk スパイク, 2026-06-26）

HANDOFF の最優先課題「**ruby.wasm が WasmKit 上で起動して `puts` できるか**」を
**Linux 上で実証した**（WasmKit は純 Swift なので Mac なしで検証できる）。
再現コードは `spike/ruby-wasm/`。本書はその結果と、`RubyVM.swift` 実装に直結する
確定事実をまとめる。

## TL;DR

✅ **CRuby 3.3.3 が WasmKit 0.2.2 上で起動し、動的 eval が通る。** Wasmtime への
差し替えは**不要**。ただし採用ビルド（`@ruby/3.x-wasm-wasi`）は WASI 単体では動かず、
**WIT component ABI のホストシム**が要る。下記の手順どおりに組めば動く（実証済み）。

検証環境: Swift 6.0.3 (Linux x86_64) / WasmKit `0.2.2` /
ruby.wasm = `@ruby/3.3-wasm-wasi` `2.9.3-2.9.4`（`ruby+stdlib.wasm`, RUBY_VERSION=3.3.3）。

## 実証できたこと（`spike/ruby-wasm` の `puts` モード出力）

| 検証項目 | 結果 |
|---|---|
| `module.instantiate`（24 ホスト import + WASI を充足） | ✅ 成功 |
| `_initialize` → `ruby-init`（VM 起動） | ✅ 成功 |
| `rb-eval-string-protect` で `puts` ＋ 文字列補間 ＋ 算術 | ✅ `HELLO ... RUBY=3.3.3; 2+3=5` |
| **eval 間の状態永続化**（`$counter=40` → 別 eval で `42`） | ✅ 成功（= `WM.handlers` 等の常駐状態が持てる） |
| 例外検出（`raise` で `state=6` = `TAG_RAISE`） | ✅ 非0 で検出可能 |
| **Ruby String を Swift へ取り出す**（`rstring-ptr` + `cabi_post`） | ✅ `"CONSUME"` を取得（= キー consume 判定の読み戻し） |
| **fd ベース RPC ラウンドトリップ**（`rbrpc`） | ✅ `move`/`windows` の 2 往復が `ROUNDTRIP_OK`（§6） |

## 確定した API / ABI（RubyVM.swift はこれに合わせる）

### 1. 採用 ruby.wasm のビルド種別が決定的に重要

`ruby/ruby.wasm` には大別 2 系統あり、**WasmKit との相性が全く違う**:

- **`@ruby/*-wasm-wasi`（npm / 本スパイクで採用）**: `_initialize` を持つ
  *reactor* で、eval を**WIT component（`rb-abi-guest` world）**として公開。
  常駐 VM ＋動的 eval が可能 → **本プロジェクトに必要なのはこちら**。
  代償として下記のホストシムと装飾名・canonical ABI が要る。
- **`*-wasip1-*`（GitHub Releases のスタンドアロン）**: import は
  `wasi_snapshot_preview1` のみで WasmKit と素直に噛むが、`_start` の
  *command* なので **eval エクスポートが無く常駐できない**（キーごとに ruby を
  起動し直す形になり、`WM.handlers` 等の常駐状態を持てない）。窓マネージャ用途では不適。

> つまり HANDOFF が「`rb_eval_string_protect` または `rb_abi_guest_*`」と書いていた
> 部分は、**実際には生 C-API シンボルは export されておらず**、WIT component の
> `rb-eval-string-protect`（後述の装飾名）を canonical ABI で呼ぶ、が正解。

### 2. instantiate には 24 関数のホストシムが必要

`ruby+stdlib.wasm` の import（`spike` の `imports` モードで全量を確認できる）:

- `wasi_snapshot_preview1`（35）… WasmKitWASI の `WASIBridgeToHost` がそのまま提供。
- `canonical_abi`（3）… リソースハンドル管理。最低限の実装が要る:
  - `resource_new_rb-abi-value (i32)->(i32)`: 新ハンドルを採番し rep を保存して返す。
  - `resource_get_rb-abi-value (i32)->(i32)`: ハンドルから rep を返す。
  - `resource_drop_js-abi-value (i32)->()`: no-op で可。
- `rb-js-abi-host`（21）… JS 相互運用フック（`eval-js` / `reflect-*` /
  `js-value-*` 等）。**窓マネージャは JS を使わないので全て stub** で可
  （戻り値の型に合わせて 0 を返す）。プレーンな eval では一切呼ばれないことを確認済み。

> ⚠️ **import / export 名はシグネチャ付きで装飾されている**（旧 witx-bindgen 形式）。
> 例: `eval-js: func(code: string) -> variant { success(...), failure(...) }` がそのまま import 名。
> export も `rb-eval-string-protect: func(str: string) -> tuple<handle<rb-abi-value>, s32>` が名前そのもの。
> → **完全一致でなく接頭辞一致 or `module.imports`/`module.exports` から実名で引く**こと。
> 実装では `module.imports` を走査してシム名・型を自動生成するのが堅い（スパイク参照）。

### 3. 確定した core 関数シグネチャ（WasmKit から取得）

| WIT export（接頭辞） | core シグネチャ | 用途 |
|---|---|---|
| `_initialize` | `() -> ()` | WASI reactor 初期化（最初に呼ぶ） |
| `cabi_realloc` | `(i32,i32,i32,i32) -> (i32)` | guest 線形メモリ確保（`realloc(0,0,align,size)`） |
| `ruby-init:` | `(i32 listptr, i32 len) -> ()` | `args: list<string>` を渡して VM 起動 |
| `rb-eval-string-protect` | `(i32 ptr, i32 len) -> (i32 retptr)` | eval。retptr 先に `(handle:i32, state:i32)` |
| `rstring-ptr` | `(i32 handle) -> (i32 retptr)` | retptr 先に `(ptr:i32, len:i32)`。後で `cabi_post_rstring-ptr(retptr)` |

その他 export（必要に応じて）: `rb-funcallv-protect`, `rb-intern`,
`rb-errinfo`, `rb-clear-errinfo`, `rb-gc-enable/disable`,
`rb-set-should-prohibit-rewind`, `asyncify_*`（非同期 fiber 用、同期 eval では不要）。

### 4. 起動シーケンス（`@ruby/wasm-wasi` の JS `initialize()` に準拠）

1. `_initialize()` を呼ぶ。
2. `ruby-init(args)` を呼ぶ。**args は各要素 NUL 終端**で `list<string>` を lower:
   既定は `["ruby.wasm\0", "-EUTF-8\0", "-e_=0\0"]`（`-e_=0` で stdin 待ちを回避）。
   `ruby-init-loadpath` は **別途呼ばない**（`ruby-init` 内で処理される。先に単独で
   呼ぶと "failed to allocate memory" でクラッシュする — スパイクで踏んだ罠）。

`list<string>` の lower: 各文字列を `cabi_realloc` で確保して UTF-8 を書き、
要素 8 バイト `(ptr:i32, len:i32)` の配列を別途確保して `(listptr, count)` を渡す。

### 5. eval と結果の取り出し

```text
ptr,len = lowerString(code)              # cabi_realloc(0,0,1,len) して UTF-8 書込
retptr  = rb-eval-string-protect(ptr,len)
handle  = mem.u32(retptr)                # 結果 VALUE の rb-abi-value ハンドル
state   = mem.u32(retptr+4)              # 0=正常, 非0=例外（6=TAG_RAISE）
```

- **truthy 判定 / 値の読み戻し**: eval の戻りは**不透明なハンドル**で、それ単体では
  真偽が分からない（`true` と `nil` で別ハンドルが返るだけ）。Swift 側で確定値が要る
  `dispatchKey` の consume 判定は、**Ruby 側で文字列に畳んでから `rstring-ptr` で読む**のが堅い:
  `eval(%Q{ (#{expr}) ? "1" : "0" })` → `rstring-ptr` で `"1"/"0"` を取得。実証済み。
- **例外時**: `state != 0` なら `rb-errinfo` で例外を取得（`rstring-ptr` で
  `.to_s` を読む等）し、`rb-clear-errinfo` で必ずクリアする（次の eval が汚染されるため）。

### 6. RPC（fd ベース）も実証済み ＋ 重要な設計修正

`spike/ruby-wasm` の `rbrpc` で **Ruby⇄Swift の同期 JSON-RPC ラウンドトリップを実証**した
（`move` → `[12,100,200]` / `windows` → `[]` の 2 往復が `ROUNDTRIP_OK`）。
フックの実装方針:

- `wasi.link` の**後に** `imports.define` で `wasi_snapshot_preview1.fd_write` / `fd_read`
  を上書きし、RPC fd のときだけ `RpcChannel.appendRequest` / `dequeueResponse` に橋渡しする。
  iovec 走査は `Caller.instance.exports[memory:]` 経由で `Memory.withUnsafeMutableBufferPointer`。
  fd_write は fd 1/2 をホスト stdout/stderr に自前で流す（WASI への委譲は不要）。

**⚠️ HANDOFF の `IO.new(3, "r+")` 設計は不可。実証で判明した修正:**

1. **phantom fd（ホスト側でフックしただけの fd）は MRI が書き込みモードで開けない。**
   `IO.new(3, "r+")` / `"w"` は `Errno::EINVAL` で失敗する（read-only の `"r"` だけ成功）。
   MRI が要求モードと fd の実アクセスモードを照合し、wasi-libc が当該 fd を read-only と
   みなすため。しかも `fd_fdstat_get` import すら呼ばれないので、フック側で偽装できない。
2. **解決策: 実在の preopen ディレクトリ配下のファイルを Ruby に開かせ、本物の
   read-write fd を得る。** スパイクは `preopens:["/rpc": <tempdir>]` を渡し、Ruby 側で
   `File.open("/rpc/sock", "w+")` で開く（MRI はこれを受理）。その fd の `fd_write`/`fd_read`
   だけを RPC チャネルへ流す（実ファイルには触れない）。`wm.rb` も `IO.new(3)` ではなく
   このファイルを開くよう更新済み。
3. **RPC fd の識別**: スパイクは「fd ≥ 4 を RPC とみなす」簡易ルール（preopen dir=fd3、
   stdio=0/1/2 を除いた最初の実 fd）。この ruby.wasm は stdlib を内蔵し RPC 以外の実ファイル
   I/O をしないため成立する（設定はホストが文字列 eval で注入する前提）。より厳密には
   `path_open` をフックして RPC パスの返り fd を捕捉する。実機検証時に堅牢化すること。

## 次セッションへの示唆

eval パイプライン（§3–5）と fd RPC（§6）はともに Linux スパイクで実証済み。`RubyVM.swift`
と `wm.rb` は本書の確定設計に更新済み（生 C-API 前提・`IO.new(3)` 前提は破棄）。残りは:

1. **実機（Mac）で縦切り確認**: `WM.windows` / `WM.move` と `default.wmrc.rb` のキーリマップ。
   RubyVM の `installRpcHooks` の fd 識別（§6-3「fd≥4」簡易ルール）を実 fd 構成で確認・堅牢化する。
2. **アーキ提案（強く推奨）**: WasmKit は Linux で動くので、Ruby ランタイム層
   （RubyVM の eval＋RPC フック）を `#if canImport(AppKit)` から外し
   **クロスプラットフォーム target に分離**すれば、`rbrpc` 相当を **CI（Linux）の自動テスト**に
   できる。`RpcBridge.dispatch` だけ macOS 実装を注入する現在の設計と相性が良い。
3. ruby.wasm 本体の取得・配置（§1 のとおり `@ruby/3.x-wasm-wasi` の `ruby+stdlib.wasm`）。
