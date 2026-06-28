# 引き継ぎ文書 (2026-06-28)

別セッションで作業を継続するための申し送り。まずこの文書 → `README.md` →
`docs/wmrc-guide.md`（Ruby で設定を書く資料）→ `docs/ruby-wasm-spike.md`（ランタイムの内部）
→ `docs/macos-window-api.md`（OS API）の順に読むと全体像が掴める。

> **状態（2026-06-28）**: **実機（Apple Silicon / macOS）で動作する `v0.1.0` をリリース済み。**
> ruby.wasm 起動・eval・fd RPC・AX でのウィンドウ操作・キーリマップ＋consume まで一通り実機確認済み。
> すべての修正は `main` にマージ済み（PR #1〜#5）。CI でタグ push（`v*`）すると `.app` を
> ビルドして GitHub Release に添付する。

## 0. プロジェクト概要（1 行）

Ruby (ruby.wasm) で挙動を記述・ホットリロードできる Swift 製 macOS ウィンドウマネージャ。
Swift 再ビルドなしに `~/.wmrc.rb` を編集 → メニューの Reload で微調整できる。

## 1. いまどこまで来たか（実機で動く）

- **配布**: GitHub Release **`v0.1.0`** に `WindowManager.app.zip`（adhoc 署名 / 未公証）。
- **CI**（`.github/workflows/ci.yml`）3 ジョブ:
  - `Linux (swift test, core)` … `swift:6.0` でコア層を `swift test`（緑）
  - `macOS (build)` … `swift build`（コンパイルゲート、緑）
  - `macOS (.app release)` … タグ push（`v*`）or 手動実行で `make app` → `.app` を Release/artifact 化
- **実機で確認済みの縦切り**: 起動 → `wm.rb`+`~/.wmrc.rb` を eval（`[wmrc] loaded` 表示）→
  `WM.windows` 等の RPC → `WM.tile`/`move`/`resize` で AX 操作 → `⌘⌥←/→/↑` でタイル＋consume。

### このプロジェクトで踏んで解決した壁（時系列）
1. **Linux でテスト可能な構造**: Apple 非依存の純ロジックを `WindowManagerCore`
   （`RpcChannel`/`RpcProtocol`/`GeometryMath`）に分離。macOS 固有は `#if canImport(AppKit)`。
2. **ruby.wasm × WasmKit の de-risk**（`docs/ruby-wasm-spike.md`）: 採用ビルドは
   `@ruby/3.x-wasm-wasi` の `ruby+stdlib.wasm`（WIT component / reactor）。eval・状態永続化・例外・
   文字列読み戻しを Linux スパイク（`spike/ruby-wasm/rbexp`）で実証。Wasmtime 差し替えは不要。
3. **fd ベース RPC**: phantom fd は MRI が書込モードで開けない（`IO.new(3,"r+")`→EINVAL）と判明。
   **preopen した実ディレクトリ配下のファイル**（`/rpc/sock`）を開いて本物の read-write fd を得る方式に。
   `RubyVM.installRpcHooks` が fd_write/fd_read をフックして `RpcChannel` へ橋渡し（`rbrpc` で実証）。
4. **CI で `.app` ビルド & Release**: タグ push / `workflow_dispatch` の `tag` 入力で Release 作成。
5. **パッケージング修正**:
   - Makefile の `RES_BUNDLE` 行末コメントで Make が値に末尾空白を含め、リソースバンドルを
     取りこぼし → `.app` が ruby.wasm 無しで起動クラッシュ。コメント別行化＋欠落時はエラーで停止。
   - `Bundle.module`（実行ファイル版）は `.app` ルート直下しか探さないが、codesign はルート直下の
     同梱物を拒否（unsealed contents）。→ `main.swift` に自前リゾルバを入れ `Contents/Resources` 配置に。
6. **実機の挙動修正**: 矢印/F キーは OS が fn(0x800000) ビットを自動付与するため、`RELEVANT_MODS` に
   fn を含めると `⌘⌥←` が一致しなかった → 照合を cmd/shift/alt/ctrl の 4 つに限定（`wm.rb`）。

## 2. 検証済み（実機で確認）

| 項目 | 状態 |
|---|---|
| コア層（RPC フレーミング/整形・座標反転） | ✅ Linux/macOS CI で `swift test` 緑 |
| ruby.wasm 起動 + eval（状態永続化/例外/文字列読み戻し） | ✅ Linux スパイク + **実機** |
| fd RPC ラウンドトリップ（Ruby⇄Swift） | ✅ Linux スパイク（`rbrpc`）+ **実機**（`WM.tile`→move/resize） |
| ネイティブ AX 操作（move/resize/raise/minimize/activate/hide） | ✅ **実機**（`⌘⌥←/→/↑` でタイル確認） |
| キーイベントタップ → Ruby ディスパッチ → consume | ✅ **実機** |
| `.app` の CI ビルド & GitHub Release | ✅ `v0.1.0` 公開済み |

## 3. 次にやること（候補）

縦切りは完成。ここからは仕上げ/拡張:

1. **配布の公証**: 現状 adhoc 署名（未公証）で、他 Mac では初回「右クリック→開く」or
   `xattr -dr com.apple.quarantine` が要る。Developer ID 署名 + notarization を入れるなら、
   証明書・Apple ID を **GitHub Secrets** に登録し `ci.yml` の sign/notarize ステップを追加する。
2. **（推奨アーキ）Ruby ランタイム層をクロスプラットフォーム target に分離**し、`rbrpc` 相当を
   **CI（Linux）の自動テスト**にする（WasmKit は Linux で動く）。回帰検出に有効。
3. **機能拡張**: スペース/Mission Control 連携、ウィンドウ間フォーカス移動、複数ディスプレイ運用、
   設定 DSL の拡充など。Ruby 側（`wm.rb` の API / `~/.wmrc.rb`）で足せるものはホットリロードで試せる。
4. **権限まわりの UX**: 入力監視/画面収録の案内、権限未付与時のフォールバック表示。

## 4. ローカルでのビルド/テスト手順

```sh
# コア層テスト（macOS / Linux 双方で可）。ruby.wasm 未取得でも通る（Makefile が空ファイルを stub）。
make test                 # == touch Resources/ruby.wasm; swift test

# ruby.wasm 本体を取得して配置（npm から ruby+stdlib.wasm を取得）。
make fetch-ruby           # -> Sources/WindowManager/Resources/ruby.wasm

# macOS で .app を作る（要 Mac）。ruby.wasm 配置 → swift build -c release → .app 組み立て + adhoc 署名。
make app
make run                  # open WindowManager.app
```

- **ruby.wasm は未コミット（.gitignore 済み）**。resource 宣言しているため未配置だと `swift build` 失敗。
  CI/Makefile の `test` は空ファイルを `touch` して回避（中身は動作には要るがコンパイル/テストには不要）。
- **CI からのリリース**: `git tag v0.1.0 && git push origin v0.1.0`、もしくは Actions から
  `ci.yml` を `workflow_dispatch`（`tag` 入力）で実行 → `macos-app` ジョブが Release に `.app` を添付。

## 5. egress（環境構築メモ）

SwiftPM 依存は GitHub から clone される（WasmKit / swift-system / swift-argument-parser）。Linux で
ローカルビルドするなら下記が要る。GitHub Actions はフルネットワークで問題なし。

- 必須: `download.swift.org`（Swift tarball）, `github.com` / `codeload.github.com`（依存 clone・tarball）
- ruby.wasm 取得: **`registry.npmjs.org`**（`@ruby/3.3-wasm-wasi` の `ruby+stdlib.wasm`）
- 注意（このプロジェクトの web 開発環境特有）: git clone がプロキシで 403 になる環境では、依存を
  tarball で vendoring する必要がある（`spike/ruby-wasm/README.md` のベンダリング手順）。
  GitHub Releases の実体ホスト `release-assets.githubusercontent.com` も塞がれていたため、ruby.wasm は
  npm 経由で取得した。

## 6. リポジトリ地図

```
Package.swift                         … 3 ターゲット（Core / 実行ファイル / Core テスト）。WasmKit・swift-system は macOS 限定リンク
Makefile                              … build / app / sign / fetch-ruby / test
.github/workflows/ci.yml              … Linux(test) + macOS(build) + macOS(.app release: タグ/手動でリリース)
docs/
  wmrc-guide.md                       … ★Ruby で ~/.wmrc.rb を書くための API リファレンス（agent 向け資料）
  ruby-wasm-spike.md                  … ruby.wasm×WasmKit の de-risk 結果・確定 ABI・RPC 設計
  macos-window-api.md                 … OS API インベントリ
spike/ruby-wasm/                      … de-risk 再現コード（rbexp=eval, rbrpc=fd RPC）。Linux/macOS で `swift run`
Sources/
  WindowManagerCore/                  … Apple 非依存・Linux テスト対象（RpcChannel / RpcProtocol / GeometryMath）
  WindowManager/                      … macOS 専用（全ファイル #if canImport(AppKit)）
    main.swift                        … エントリ + メニューバー + 起動順 + リソースリゾルバ（Bundle.module 非依存）
    Native/ WindowAPI/ScreenAPI/AppAPI/EventTap/Geometry.swift
    Ruby/  RubyVM.swift（ruby.wasm 起動・eval・fd RPC フック）, RpcBridge.swift（メソッド振り分け）
    Permissions.swift
    Resources/ wm.rb（WM ライブラリ）, default.wmrc.rb（サンプル設定）, (ruby.wasm: 未コミット)
Tests/WindowManagerCoreTests/         … RpcChannel/RpcProtocol/GeometryMath のテスト
bundle/ Info.plist, WindowManager.entitlements
```

## 7. 落とし穴メモ

- **座標系**: AppKit=bottom-left / CG・AX=top-left。変換は `GeometryMath`（純）＋ `Geometry`（NSScreen ラッパ）。
  Ruby へ渡す/から受ける座標は **top-left 統一**。
- **権限**: アクセシビリティ（AX 操作・イベントタップに必須）、画面収録（ウィンドウタイトル取得）、
  入力監視（環境により必要）。`Permissions.swift` 参照。未付与だと `WM.windows` が空/操作が false。
- **CGWindowID → AXUIElement** に private シンボル `_AXUIElementGetWindow` を使用（`WindowAPI.swift`）。
  yabai 等と同様。OS 更新で消えるリスクは低いが private。
- **RPC は preopen ファイル経由**（旧 `IO.new(3)` ではない）。Ruby 側 `wm.rb` の `RPC_PATH = "/rpc/sock"`
  と Swift 側 `RubyVM.rpcGuestDir = "/rpc"` を一致させること。fd 識別は「fd≥4 を RPC」の簡易ルール
  （`docs/ruby-wasm-spike.md` §6）。Ruby 側が他に実ファイル I/O をしない前提で成立。
- **修飾キーの fn**: 矢印/F キーは OS が fn ビットを自動付与する。照合は cmd/shift/alt/ctrl のみ
  （`wm.rb` の `RELEVANT_MODS`）。fn を修飾キーとしては使えない。
- **ターミナル起動で出力が見える**: `./WindowManager.app/Contents/MacOS/WindowManager` だと Ruby の
  `puts`/`warn`/例外が標準出力に出る（`open` 起動だと見えない）。デバッグに有用。
- WasmKit の API は版で揺れる。`Package.resolved`（Mac で生成）でピン留めしてから実装を合わせる。
