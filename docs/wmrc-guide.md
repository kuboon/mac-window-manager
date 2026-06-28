# `~/.wmrc.rb` スクリプティングガイド（Ruby API リファレンス）

このファイルは **coding agent / 人間が `~/.wmrc.rb` を書くための完全な資料**。これと
`Sources/WindowManager/Resources/wm.rb`（実装の正本）だけ読めば設定を書ける。
OS API の背景は `docs/macos-window-api.md`、ランタイムの仕組みは `docs/ruby-wasm-spike.md`。

---

## 0. 30 秒でわかる仕組み

- アプリ（`WindowManager.app`）は **メニューバー常駐**。中に **ruby.wasm（CRuby 3.3）** を
  WasmKit で抱えている。
- 起動時に標準ライブラリ `wm.rb`（`WM` モジュール）→ あなたの **`~/.wmrc.rb`** の順で eval する。
- `~/.wmrc.rb` を編集して、メニューバー `▦` の **Reload config**（`⌘R`）を押すと**再ビルド不要で反映**。
- Ruby から `WM.move(...)` 等を呼ぶと、ホスト（Swift）へ**同期 RPC** され、AppKit/Accessibility で
  実際のウィンドウ操作が行われる。
- キーは `WM.on_key(...)` で登録。ブロックが truthy を返すと、そのキーは **consume**（他アプリに渡さない）。

最小例:

```ruby
# ⌘⌥F でフォーカス中ウィンドウを最大化（可視領域いっぱい）
WM.on_key(0x03, [:cmd, :alt]) do      # 0x03 = F キー
  id = WM.focused_window
  WM.tile(id, 0.0, 0.0, 1.0, 1.0) if id
  true                                 # consume
end
```

---

## 1. 座標系（重要）

- **原点は左上 (top-left)、Y は下向き**。グローバル座標（全ディスプレイをまたぐ仮想デスクトップ）。
  AppKit 由来の bottom-left ではなく、すべて top-left に変換済みの値が来る/渡す。
- 単位は **ポイント**（Retina スケールではない論理ピクセル）。
- ウィンドウ配置は基本 `tile`（可視領域に対する割合指定）を使うと、メニューバー/Dock を避けた
  `visible_*` 領域基準で計算してくれるので楽。

---

## 2. `WM` API リファレンス

すべて `WM.` 始まり（`WM` はモジュールの特異メソッド群）。RPC は**同期**で、ホストの応答まで
ブロックする。失敗時は後述の通り。

### 2.1 列挙（読み取り）

| メソッド | 返り値 |
|---|---|
| `WM.windows` | ウィンドウの配列（下記 shape）。オンスクリーンの通常ウィンドウのみ（レイヤ0）。 |
| `WM.screens` | ディスプレイの配列（下記 shape）。 |
| `WM.apps` | 起動中アプリの配列（通常 UI アプリのみ）。 |
| `WM.focused_window` | フォーカス中ウィンドウの **id（Integer）**。無ければ `nil`。 |

**window の shape**（`WM.windows` の各要素 / キーは文字列）:

```ruby
{
  "id"        => 12345,        # CGWindowID（move/resize 等に渡す識別子）
  "pid"       => 678,          # 所有プロセス
  "app"       => "Safari",     # アプリ名
  "title"     => "...",        # ウィンドウタイトル（※画面収録権限が無いと "" になる）
  "x" => 0.0, "y" => 25.0,     # 左上座標（top-left, グローバル）
  "w" => 1440.0, "h" => 875.0, # 幅・高さ
  "layer"     => 0,            # ウィンドウレイヤ（通常アプリは 0）
  "on_screen" => true,
}
```

**screen の shape**（`WM.screens` の各要素）:

```ruby
{
  "x" => 0.0, "y" => 0.0, "w" => 1920.0, "h" => 1080.0,  # ディスプレイ全体（top-left）
  "visible_x" => 0.0, "visible_y" => 25.0,               # メニューバー/Dock を除いた可視領域
  "visible_w" => 1920.0, "visible_h" => 1023.0,
  "scale" => 2.0,                                          # backingScaleFactor
  "name"  => "Built-in Retina Display",
}
```
`WM.screens.first` がメイン（通常は配列先頭）。

**app の shape**（`WM.apps` の各要素）:

```ruby
{ "pid" => 678, "name" => "Safari", "bundle_id" => "com.apple.Safari",
  "active" => true, "hidden" => false }
```

### 2.2 操作（副作用）

いずれも成功で `true` / 失敗で `false` を返す（対象が見つからない・権限不足など）。

| メソッド | 説明 |
|---|---|
| `WM.move(window_id, x, y)` | ウィンドウ左上を (x, y)（top-left, グローバル）へ移動。 |
| `WM.resize(window_id, w, h)` | ウィンドウサイズを (w, h) に設定。 |
| `WM.raise_window(window_id)` | ウィンドウを前面へ。 |
| `WM.minimize(window_id, flag = true)` | 最小化（`flag=false` で復元）。 |
| `WM.activate(pid)` | 指定 pid のアプリを前面化。 |
| `WM.hide_app(pid)` | 指定 pid のアプリを隠す。 |

### 2.3 便利関数

```ruby
# 可視領域に対する割合 (fx, fy, fw, fh) でウィンドウを配置する。
# 例: tile(id, 0.0, 0.0, 0.5, 1.0) = 左半分 / (0.5,0,0.5,1.0) = 右半分 / (0,0,1,1) = 最大化
WM.tile(window_id, fx, fy, fw, fh, screen: WM.screens.first)
```
`screen:` を別ディスプレイの screen ハッシュにすれば、そのディスプレイ基準で配置できる。

### 2.4 キーイベント DSL

```ruby
WM.on_key(keycode, mods = [], &block)  # ハンドラ登録
WM.handlers                            # 登録済みハンドラ一覧（配列）
WM.reset!                              # 全ハンドラ削除（Reload 時にホストが自動で呼ぶ）
```
- `keycode`: 仮想キーコード（§4 の表）。**物理キー位置**であって文字ではない（US 配列基準）。
- `mods`: `[:cmd, :alt]` のような修飾キーシンボルの配列（§3）。
- `&block`: そのキーが押された時に実行。**truthy を返すと consume**（OS/他アプリに渡さない＝リマップ）。
  block は `ev`（`{ keycode:, flags:, mods: }`）を 1 引数で受け取れる。

---

## 3. 修飾キー（mods）

`WM.on_key` の `mods` に使えるシンボル:

| シンボル | キー |
|---|---|
| `:cmd` | ⌘ Command |
| `:shift` | ⇧ Shift |
| `:alt` | ⌥ Option (Alt) |
| `:ctrl` | ⌃ Control |

> **`:fn` は照合に使えない**。矢印キーや F キーを押すと macOS が自動で fn(secondaryFn) ビットを
> 立てるため、照合に含めると矢印ショートカットが壊れる。よって判定は cmd/shift/alt/ctrl の 4 つのみ
> （`wm.rb` の `RELEVANT_MODS` 参照）。fn を修飾キーとして使う用途は非対応。

修飾キー無しのハンドラは `mods` を省略（または `[]`）。**完全一致**で判定される
（例: `[:cmd]` 登録なら ⌘ だけ。⌘⇧ では発火しない）。

---

## 4. 主要キーコード表（US 配列・物理位置）

`keycode` は Carbon の仮想キーコード（`kVK_*`）。よく使うものを抜粋（16進/10進）:

```
英字:  A=0x00 S=0x01 D=0x02 F=0x03 H=0x04 G=0x05 Z=0x06 X=0x07 C=0x08 V=0x09
       B=0x0B Q=0x0C W=0x0D E=0x0E R=0x0F Y=0x10 T=0x11 O=0x1F U=0x20 I=0x22
       P=0x23 L=0x25 J=0x26 K=0x28 N=0x2D M=0x2E
数字:  1=0x12 2=0x13 3=0x14 4=0x15 5=0x17 6=0x16 7=0x1A 8=0x1C 9=0x19 0=0x1D
矢印:  ←=0x7B(123) →=0x7C(124) ↓=0x7D(125) ↑=0x7E(126)
特殊:  Return=0x24 Tab=0x30 Space=0x31 Delete=0x33 Esc=0x35
       ;=0x29 '=0x27 ,=0x2B .=0x2F /=0x2C \=0x2A [=0x21 ]=0x1E `=0x32 -=0x1B ==0x18
ファンクション: F1=0x7A F2=0x78 F3=0x63 F4=0x76 F5=0x60 F6=0x61 F7=0x62 F8=0x64
               F9=0x65 F10=0x6D F11=0x67 F12=0x6F
```
全コードは Carbon `HIToolbox/Events.h` の `kVK_*` を参照。`default.wmrc.rb` も実例として読むとよい。

---

## 5. レシピ集

```ruby
# --- 半分タイル（⌘⌥ + 矢印）-----------------------------------------------
fw = ->(fx, fw) { id = WM.focused_window; WM.tile(id, fx, 0.0, fw, 1.0) if id; true }
WM.on_key(0x7B, [:cmd, :alt]) { fw.(0.0, 0.5) }   # ← 左半分
WM.on_key(0x7C, [:cmd, :alt]) { fw.(0.5, 0.5) }   # → 右半分
WM.on_key(0x7E, [:cmd, :alt]) { fw.(0.0, 1.0) }   # ↑ 最大化

# --- 1/4 タイル（⌘⌥ + U/I/J/K）-------------------------------------------
quad = ->(fx, fy) { id = WM.focused_window; WM.tile(id, fx, fy, 0.5, 0.5) if id; true }
WM.on_key(0x20, [:cmd, :alt]) { quad.(0.0, 0.0) }  # U 左上
WM.on_key(0x22, [:cmd, :alt]) { quad.(0.5, 0.0) }  # I 右上
WM.on_key(0x26, [:cmd, :alt]) { quad.(0.0, 0.5) }  # J 左下
WM.on_key(0x28, [:cmd, :alt]) { quad.(0.5, 0.5) }  # K 右下

# --- 中央寄せ（少し小さく）------------------------------------------------
WM.on_key(0x08, [:cmd, :alt]) do                    # C
  if (id = WM.focused_window)
    WM.tile(id, 0.1, 0.1, 0.8, 0.8)
  end
  true
end

# --- 次のディスプレイへ移動 -----------------------------------------------
WM.on_key(0x2D, [:cmd, :alt]) do                    # N
  id = WM.focused_window or next true
  win = WM.windows.find { |w| w["id"] == id }
  scr = WM.screens
  next true if scr.size < 2
  # 今いる画面の次の画面へ、左半分で置く
  cur = scr.index { |s| win && win["x"] >= s["x"] && win["x"] < s["x"] + s["w"] } || 0
  WM.tile(id, 0.0, 0.0, 1.0, 1.0, screen: scr[(cur + 1) % scr.size])
  true
end

# --- アプリ起動/前面化（Finder を前面に）----------------------------------
WM.on_key(0x03, [:cmd, :ctrl]) do                   # ⌘⌃F
  finder = WM.apps.find { |a| a["bundle_id"] == "com.apple.finder" }
  WM.activate(finder["pid"]) if finder
  true
end

# --- consume せず観測だけ（false を返す）----------------------------------
WM.on_key(0x31, [:cmd, :shift]) do                  # ⌘⇧Space
  warn "windows = #{WM.windows.size}"
  false                                             # 他アプリにもイベントを渡す
end
```

---

## 6. ランタイムの制約（生成時に守ること）

- **Ruby は CRuby 3.3（`ruby+stdlib.wasm`）**。標準ライブラリは使える（`json` は wm.rb が require 済み）。
- **使えない/避けるべきもの**:
  - ネイティブ拡張を持つ gem（`gem install` 不可、C 拡張不可）。pure-Ruby のものを `~/.wmrc.rb` に
    インライン展開するなら可。
  - スレッド/Fiber を使った並行処理、ブロッキング I/O、ネットワーク、子プロセス（`system`/`exec`）は
    基本的に不可・非推奨（WASI 環境のため）。
  - ファイル I/O は基本不要（設定はホストが文字列として eval する）。`/rpc/sock` は**触らない**
    （RPC 専用の予約 fd）。
- **RPC は同期**。`WM.windows` などは結果が返るまでブロックする。キーのブロック内で大量に呼ぶと
  入力のレイテンシになるので、必要な分だけ呼ぶ。
- **ブロックは短く同期で**。例外は `_dispatch_key` 内で rescue され `warn` に出るだけ（アプリは
  落ちない）。エラー時はそのキーは consume されず素通しになる。

---

## 7. 落とし穴・デバッグ

- **出力を見るには**: アプリを **ターミナルから直接起動**すると `puts`/`warn`/例外が標準出力・
  標準エラーに出る:
  ```sh
  ./WindowManager.app/Contents/MacOS/WindowManager
  ```
  Finder の `open` 起動だと出力は見えない。
- **矢印/F キーの fn ビット**: §3 のとおり対応済み（cmd/shift/alt/ctrl のみで照合）。新しいキーを
  足すときも、修飾キーは原則この 4 種で考える。
- **タイトルが空**: `title` が `""` のときは「画面収録」権限が未許可。システム設定で許可する。
- **ウィンドウが動かない/キーが効かない**:
  - アクセシビリティ権限（必須）を確認（システム設定 ▸ プライバシーとセキュリティ ▸ アクセシビリティ）。
  - 一部アプリ（フルスクリーン中、サンドボックス強・非標準ウィンドウ）は AX 操作を受け付けないことがある。
  - 他のキーボード/ウィンドウ系ツールとショートカットが競合する場合は別キーに変える。
- **ホットリロード**: 編集 → メニュー `▦` ▸ Reload config（`⌘R`）。`WM.reset!` はリロード時に
  ホストが自動で呼ぶので、`~/.wmrc.rb` の冒頭で自前のグローバル状態を初期化したい場合は明示的に。

---

## 8. coding agent 向けチェックリスト

`~/.wmrc.rb` を生成するときは:

1. すべて `WM.` の公開メソッド（§2）だけを使う。内部メソッド（`_io` / `call` / `_dispatch_key` /
   定数 `MOD` `RELEVANT_MODS` `RPC_PATH`）には触らない。
2. キーは `WM.on_key(keycode, [mods]) { ... }`。**keycode は §4 の数値**、mods は §3 の 4 シンボルのみ。
3. リマップなら block の最後で `true`（consume）、観測だけなら `false`。
4. ウィンドウ配置は基本 `WM.tile`（割合）。絶対座標が必要なときだけ `move`/`resize`（top-left）。
5. `WM.focused_window` は `nil` を返しうる → 必ず nil ガード。
6. RPC 結果のハッシュは**文字列キー**（`w["id"]`、`s["visible_w"]`）。
7. ネットワーク/子プロセス/native gem/スレッドは使わない（§6）。
8. 失敗は静かに false / nil になる設計。重要な前提は自分でチェックする。

実装の正本は `Sources/WindowManager/Resources/wm.rb`、デフォルト設定例は
`Sources/WindowManager/Resources/default.wmrc.rb`。
