# 引き継ぎ文書 (2026-06-26)

別セッションで作業を継続するための申し送り。まずこの文書 → `README.md` →
`docs/macos-window-api.md` の順に読むと全体像が掴める。

## 0. プロジェクト概要（1 行）

Ruby (ruby.wasm) で挙動を記述・ホットリロードできる Swift 製 macOS ウィンドウマネージャ。
Swift 再ビルドなしに `~/.wmrc.rb` を編集して微調整できることが目的。

## 1. いまどこまで来たか

- **ブランチ**: `claude/swift-macos-ruby-wasm-yq7vfp`（このブランチで開発を続ける）
- **PR**: kuboon/mac-window-manager **#1**（ドラフト）
- **CI**: `.github/workflows/ci.yml` の 2 ジョブとも **緑**
  - `Linux (swift test, core)` … `swift:6.0` コンテナでコア層を `swift test` → **21 テスト合格**
  - `macOS (build)` … `swift build` が WasmKit/ruby.wasm 連携含めて**コンパイル成功**

### 直近のセッションでやったこと
1. **Linux でテスト可能にする構造変更**（本題）
   - Apple 非依存の純ロジックを新ライブラリ **`WindowManagerCore`** に分離
     （`RpcChannel` / `RpcProtocol` / `GeometryMath`）。dispatcher を注入式にして macOS API と切り離した。
   - macOS 固有ソースは全て `#if canImport(AppKit)` で囲い、**WasmKit / swift-system を
     macOS 限定リンク**に。Linux ではコア層＋実行ファイルのスタブのみビルドされる。
   - `App.swift` → `main.swift` に改名（top-level コードは `main.swift` のみ許可）＋ Linux 用スタブ entry point。
   - `WindowManagerCoreTests`（XCTest）を追加。
   - CI を 2 段化（Linux=ゲート、macOS=ゲート）。
2. **WasmKit グルーの既存バグを 3 件修正**（CI が示すたびに対応。いずれも Linux 化とは無関係の skeleton 起因）
   - `FilePath` を `import SystemPackage` せず使用 → import 追加 + swift-system 依存追加
   - `WASIBridgeToHost` の `preopens` は `[String: String]`（`FilePath` ではない）
   - 現行 WasmKit の `wasi.start(_:)` は `store:` 引数を取らない

## 2. 検証済み / 未検証（正直な現状）

| 項目 | 状態 |
|---|---|
| コア層ロジック（RPC フレーミング/整形・座標反転） | ✅ Linux/macOS の CI で `swift test` 緑 |
| ネイティブ Swift ラッパ（`WindowAPI`/`ScreenAPI`/`AppAPI`/`EventTap`/`Permissions`） | ✅ macOS で**コンパイル**は通る |
| `RubyVM`（WasmKit インスタンス化）| ✅ コンパイル通る / ❌ **動作未検証** |
| ruby.wasm の評価エントリ呼び出し（`rb_eval_string_protect` 等）| ❌ **未実装**（`RubyVM.swift` の `evaluateOnVM` / `installRpcHooks` は骨格のみ） |
| 実機でのウィンドウ操作・キーイベント consume | ❌ **未検証**（要 Mac + アクセシビリティ権限） |

> ⚠️ コンパイルが通る ≠ 動く。`RubyVM` の中身（fd フック・eval）は TODO(on-mac) のまま。

## 3. 次にやること（優先順）

1. **環境の egress 許可**（ユーザが用意中）。Linux で `swift test` をローカル実行するため、
   下記ドメインを 443/CONNECT で許可（§5 参照）。許可後、Swift を入れてローカルで緑を再現する。
2. **de-risk: ruby.wasm が WasmKit 上で起動して `puts` できるか**を最優先で確認
   （ダメなら WASI 完全対応の Wasmtime への差し替えを検討）。
3. `RubyVM.swift` の 2 つの統合ポイントを実機で実装・確定:
   - `installRpcHooks`: `fd_write`/`fd_read`（fd=3）を `channel.appendRequest` /
     `channel.dequeueResponse` に橋渡し（WasmKit の Imports/Caller/Memory API に合わせる）。
   - `evaluateOnVM`: 採用する ruby.wasm ビルドの eval エクスポート
     （`rb_eval_string_protect` または `rb_abi_guest_*`）を呼ぶ。線形メモリ確保が要る。
     → `@ruby/wasm-wasi`(JS) の `RubyVM` 実装を設計図にする。
4. ruby.wasm 本体を取得して `Sources/WindowManager/Resources/ruby.wasm` に配置（§4）。
5. 縦切りの動作確認: `WM.windows` / `WM.move` と、サンプルのキーリマップ（`default.wmrc.rb`）。

## 4. ローカルでのビルド/テスト手順

```sh
# コア層テスト（macOS / Linux 双方で可）。ruby.wasm 未取得でも通る（Makefile が空ファイルを stub）。
make test            # == touch Resources/ruby.wasm; swift test

# macOS で .app を作る（要 Mac）
make app             # swift build → WindowManager.app 組み立て + adhoc 署名
make run

# ruby.wasm 本体（未コミット, .gitignore 済み）。GH リリース or npm から取得して配置:
#   Sources/WindowManager/Resources/ruby.wasm
```

- **ruby.wasm を resource 宣言しているため未配置だと `swift build` が失敗する**。CI と Makefile は
  空ファイルを `touch` して回避している（中身は動作には要るが、コンパイル/テストには不要）。

## 5. 必要な egress ホワイトリスト（環境構築用）

`download.swift.org` だけでは不足。**SwiftPM が依存を GitHub から clone する**ため GitHub 系も必須
（WasmKit を macOS 限定リンクにしても、依存の clone 自体は Linux でも走る）。

**必須**
- `download.swift.org` … Swift ツールチェイン tarball
- `github.com` … `swiftwasm/WasmKit`・`apple/swift-system`（+推移依存）の clone
- `codeload.github.com` … git archive/clone 実体
- `objects.githubusercontent.com` … GH リリース/LFS アセット

**たぶん既に開いている**（前回 base apt は通った。落ちたのは不要な PPA のみ）
- `archive.ubuntu.com`, `security.ubuntu.com` … apt の system ライブラリ

**任意**: `swift.org`/`www.swift.org`（swiftly 利用・署名検証時）, `raw.githubusercontent.com`

**追加不要**（プロキシの noProxy で素通し済み）: `registry.npmjs.org`（ruby.wasm を npm 取得する場合）, `pypi.org`, `index.crates.io` ほか

検証に使った tarball URL（swiftly なしの手動 install）:
```
https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz
```
> 注意: この環境ではプロキシが `download.swift.org` を 403 で遮断していたため Swift を入れられず、
> 検証は GitHub Actions（フルネットワーク）で実施した。egress が開けばローカルで同じ緑を再現可能。

## 6. リポジトリ地図

```
Package.swift                         … 3 ターゲット（Core / 実行ファイル / Core テスト）。WasmKit・swift-system は macOS 限定
Makefile                              … build / app / test / sign（test は ruby.wasm を stub）
.github/workflows/ci.yml              … Linux(swift test) + macOS(build)
docs/macos-window-api.md              … OS API インベントリ（要件「全機能をパラメタ付きで列挙」）
Sources/
  WindowManagerCore/                  … Apple 非依存・Linux テスト対象
    RpcChannel.swift                  … fd 上の同期 RPC フレーミング（dispatcher 注入）
    RpcProtocol.swift                 … パース/整形/引数の型強制
    GeometryMath.swift                … bottom-left ⇄ top-left 反転（純ロジック）
  WindowManager/                      … macOS 専用（全ファイル #if canImport(AppKit)）
    main.swift                        … @main 相当（top-level）+ Linux スタブ
    Native/ WindowAPI/ScreenAPI/AppAPI/EventTap/Geometry.swift
    Ruby/  RubyVM.swift（★TODO on-mac）, RpcBridge.swift
    Permissions.swift
    Resources/ wm.rb, default.wmrc.rb, (ruby.wasm: 未コミット)
Tests/WindowManagerCoreTests/         … RpcChannel/RpcProtocol/GeometryMath のテスト
bundle/ Info.plist, WindowManager.entitlements
```

## 7. 落とし穴メモ

- **座標系**: AppKit=bottom-left / CG・AX=top-left。変換は `GeometryMath`（純）＋ `Geometry`（NSScreen ラッパ）の 1 箇所のみ。Ruby へ渡す座標は top-left 統一。
- **権限**: アクセシビリティ（AX 操作・イベントタップ必須）、画面収録（ウィンドウタイトル）、入力監視。`Permissions.swift` 参照。
- **CGWindowID → AXUIElement** の対応付けに private シンボル `_AXUIElementGetWindow` を使用（`WindowAPI.swift`）。yabai 等と同様。OS 更新で消えるリスクは低いが private。
- **RPC は fd=3**。Ruby 側（`wm.rb`）と Swift 側（`RubyVM.rpcFD`）で番号を一致させること。
- WasmKit の API は版で揺れる。`Package.resolved`（Mac で生成）でピン留めしてから実装を合わせる。
