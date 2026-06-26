# ruby.wasm × WasmKit 検証スパイク

`Sources/WindowManager/Ruby/RubyVM.swift` の 2 大未検証ポイント（WasmKit の
API シグネチャと ruby.wasm の eval エントリ）を**実機なしで de-risk** するための
最小実行ファイル。**Linux でも動く**（WasmKit は純 Swift）。

結果の要約は `docs/ruby-wasm-spike.md` を参照。要点だけ:
ruby.wasm（`@ruby/3.x-wasm-wasi`）は WASI 単体では動かず、**WIT component ABI**
（装飾された export 名・`cabi_realloc` 文字列受け渡し・間接 return）と
**24 関数のホストシム**（`canonical_abi` 3 + `rb-js-abi-host` 21）が必要。
これらを与えれば CRuby 3.3 が起動し、`puts` / 状態の永続化 / 例外 / 文字列の取り出しまで通る。

## 実行

```sh
# 1) ruby.wasm を npm から取得（GitHub Releases の release-assets ホストが
#    塞がれている環境向け。通常は ruby/ruby.wasm の Releases でもよい）
TARBALL=$(curl -sS https://registry.npmjs.org/@ruby/3.3-wasm-wasi \
  | python3 -c "import sys,json;d=json.load(sys.stdin);v=d['dist-tags']['latest'];print(d['versions'][v]['dist']['tarball'])")
curl -sSL "$TARBALL" | tar -xz          # -> package/dist/ruby+stdlib.wasm

# 2) 実行
swift run -c release rbexp package/dist/ruby+stdlib.wasm puts     # eval して puts
swift run -c release rbexp package/dist/ruby+stdlib.wasm imports  # import 一覧（ホストシムの全量）
swift run -c release rbexp package/dist/ruby+stdlib.wasm exports  # export 一覧（eval エントリ等）
```

期待される `puts` 出力（抜粋）:

```
HELLO from ruby.wasm on WasmKit (Linux); RUBY=3.3.3; 2+3=5
persisted: $counter + 2 = 42
[raise] handle=4 state=6 (state!=0 => exception raised)
lifted Ruby String result = "CONSUME"
```

## git clone が塞がれた環境でのベンダリング手順

SwiftPM の依存 clone がプロキシで 403 になる場合（任意の github repo の
clone が拒否される web セッション等）は、tarball で依存をベンダリングして
ローカル path 依存に差し替える。WasmKit は `SWIFTCI_USE_LOCAL_DEPS` を見て
`../swift-argument-parser` と `../swift-system` を path 依存にするので、それを利用する:

```sh
mkdir vendor && cd vendor
for u in \
  "https://codeload.github.com/swiftwasm/WasmKit/tar.gz/refs/tags/0.2.2|WasmKit" \
  "https://codeload.github.com/apple/swift-argument-parser/tar.gz/refs/tags/1.5.1|swift-argument-parser" \
  "https://codeload.github.com/apple/swift-system/tar.gz/refs/tags/1.5.0|swift-system"; do
  url=${u%|*}; name=${u#*|}; curl -sSL "$url" | tar -xz; mv */ "$name" 2>/dev/null || true
done
# Package.swift の URL 依存を .package(path: "vendor/WasmKit") /(path: "vendor/swift-system") に
# 差し替え、ビルド時に SWIFTCI_USE_LOCAL_DEPS=1 を設定する。
```

> codeload.github.com / registry.npmjs.org は HTTPS プロキシ経由で到達可能。
> 一方 release-assets.githubusercontent.com（GitHub Releases の実体）と
> 任意 repo の git clone は遮断されていた（2026-06 時点のこの環境）。
