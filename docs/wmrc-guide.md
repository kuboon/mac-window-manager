---
title: API リファレンス
nav_order: 4
---

# `~/.wmrc.rb` スクリプティングガイド（Ruby API リファレンス）

このファイルは **coding agent / 人間が `~/.wmrc.rb` を書くための完全な資料**。これと
`Sources/WindowManager/Resources/wm.rb`（実装の正本）だけ読めば設定を書ける。
OS API の背景は [macOS Window API]({{ '/macos-window-api' | relative_url }})、
ランタイムの仕組みは [ruby.wasm スパイク]({{ '/ruby-wasm-spike' | relative_url }})。
**書く前にコピペで済ませたい人は [レシピ集]({{ '/recipes/' | relative_url }}) へ。**

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
- `&block`: そのキーが押された時に実行。block は `ev`（`{ keycode:, flags:, mods: }`）を 1 引数で受け取れる。
- **consume の既定**: マッチしたキーは**デフォルトで consume される**（OS/他アプリに渡さない＝リマップ）。
  わざわざ末尾に `true` を書く必要はない。**OS の通常動作を残したい（素通りさせたい）ときだけ
  ブロックで明示的に `false` を返す**。
  - 理由: `WM.tile` 等の戻り値（内部の RPC 結果）は falsy とは限らないため、「明示しなければ素通り」
    だと不安定になる。そこで「マッチ＝consume、例外的に `false` で素通り」を既定にしている。
  - `nil` を返しても consume される（`false` だけが素通り）。
  - 注: 全キーを掴む `WM.on_any_key`（§2.7）は逆で、**明示的に truthy を返したときだけ consume**
    （全キーを見るため、デフォルト consume だと全入力を飲み込んでしまうので）。

### 2.5 ディスプレイ構成変更フック

外部ディスプレイの**接続/切断・配置変更・解像度変更**で呼ばれるハンドラを登録できる。

```ruby
WM.on_screens_changed do |screens|   # screens は WM.screens と同じ配列
  if screens.size > 1
    # ドック時（外部ディスプレイあり）の処理
  else
    # ノート単体の処理
  end
end
```
- ブロックは現在の `screens` 配列を 1 引数で受け取る。
- **AppKit は 1 回の抜き差しで複数回通知することがある**ので、ハンドラは**冪等**に書く
  （同じ入力で何度呼ばれても同じ結果になるように）。
- `WM.screen_handlers` で登録済み一覧、`WM.reset!` で（キーハンドラと共に）クリア。

### 2.6 永続ストレージ（再起動をまたぐ保存）

ホスト側の JSON ファイル（`~/Library/Application Support/WindowManager/state.json`）に
**再起動をまたいで残る** KV ストア。`~/.wmrc.rb` から自由にファイルへ書けない代わりにこれを使う。

```ruby
WM.save(key, value)   # value は JSON 化可能（Hash/Array/数値/文字列/真偽/nil）
WM.load(key)          # 保存値を返す。無ければ nil
```
- `nil` を save するとそのキーは削除される。
- 用途: ウィンドウ位置スナップショット、現在のモード、トグル状態の記憶など。

### 2.7 生キーフック `WM.on_any_key`（モード/リーダーキーの土台）

**全キーイベントを Ruby に渡す**最下層のフック。`on_key` の照合より先に評価され、
truthy を返すとそのイベントを consume して通常照合をスキップする。これ 1 個あれば、
リーダーキー（F1 → t で tiling…）やモード、which-key などを **すべて Ruby で**書ける。

```ruby
WM.on_any_key do |ev|
  # ev = { keycode:, mods:, flags:, key_down: }
  next false unless ev[:key_down]   # 通常は keyDown だけ見る
  # ... 好きなロジック ...
  false                              # true を返したキーだけ consume
end
```
- **keyDown / keyUp / 修飾キー変化すべてで呼ばれる**（`ev[:key_down]` で判別）。
  hold 系もやれるが、keyUp を consume するとキーが押しっぱなし扱いになりうるので注意。
- 複数登録可。登録順に評価し、最初に truthy を返したものが consume する。
- `WM.reset!`（Reload 時）でクリア。**モード状態は自前の変数で持つ**（下の §5 レシピ参照）。

### 2.8 ドラッグ&ドロップ `WM.on_drag_end`（snap の土台）

他アプリのウィンドウを**マウスでドラッグして離した瞬間**に呼ばれる**観測専用**フック。
端への吸着（snap）などを Ruby 側で実装するための入口。

```ruby
WM.on_drag_end do |ev|
  # ev = { window:, x:, y: }  （x,y は top-left グローバルなカーソル位置）
  # ev[:window] はドラッグしていたウィンドウ id（ドラッグ開始時の前面ウィンドウ）
end
```
- **consume しない**ので、OS の通常のウィンドウ移動はそのまま行われ、その後に好きな配置へ寄せる
  （= ドロップ位置を見て `WM.tile` で吸着）。
- 1 ドラッグにつき**ドロップ時に 1 回**だけ呼ばれる（軽い）。ドラッグ中のリアルタイム・プレビューは
  現状なし（将来 Swift 側オーバーレイで対応予定）。
- `WM.reset!`（Reload 時）でクリア。

### 2.9 Space（仮想デスクトップ）切替フック `WM.on_space_changed`

Mission Control の**アクティブ Space が切り替わった**ときに呼ばれるハンドラ。public 通知
（`activeSpaceDidChange`）ベースなので **private API も SIP 緩和も不要**。

```ruby
WM.on_space_changed do |wins|
  # wins は「切替先＝今アクティブな Space に出ている窓」の配列（WM.windows と同じ形）
  # 例: この Space に来たら特定レイアウトを当て直す
end
```
- ブロックは**切替先 Space の窓一覧**を 1 引数で受け取る（`WM.windows` と同じ）。
- **できないこと（重要な制約）**:
  - 「**どの** Space か」（番号/ID）は分からない。public API に無いため。
  - 「**別の**（今見えていない）Space にある窓」は列挙できない。取れるのは常に
    **アクティブ Space の窓**だけ。
  - どちらも private SkyLight（yabai が使う層）が必要で、本システムは未提供。
- `WM.space_handlers` で登録済み一覧、`WM.reset!`（Reload 時）でクリア。

> 補足: 「フォーカス窓を隣の Space へ移動」のような **Space 操作**は、private SkyLight
> （`SLSMoveWindowsToManagedSpaces` 等。SIP 緩和は不要な層）が必要で現状未提供。Raycast 等は
> この層を使っている。native Spaces を**使わず**ワークスペースを再現したい場合は
> [AeroSpace から]({{ '/from-aerospace' | relative_url }}) の「仮想ワークスペース」（`WM.move` で
> 画面外退避）を参照。

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

## 5. レシピ（抜粋）

> module 化された「貼るだけ」のレシピ（BSP・仮想ワークスペース・ドラッグ吸着・
> サイズサイクルなど）は **[レシピ集]({{ '/recipes/' | relative_url }})** にまとめてある。
> ここでは API の使い方を示す小さな例だけを載せる。

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

### レイアウト保存/復元 ＋ 自動モード切替（ディスプレイ構成ごと）

```ruby
# 現在のディスプレイ構成キー（ノート単体／ドック時で別レイアウトを持てる）
def layout_signature
  WM.screens.map { |s| s["name"] }.sort.join(" | ")
end

# ⌘⌥S: 全ウィンドウ位置を今の構成キーで保存
WM.on_key(0x01, [:cmd, :alt]) do                    # S
  snap = WM.windows.map { |w| w.slice("app", "title", "x", "y", "w", "h") }
  WM.save("layout:#{layout_signature}", snap)
  true
end

# ⌘⌥R: 保存レイアウトを復元（再起動後に手動で1回押す）
# CGWindowID は再起動で変わるため app + title で照合（title 変化時は同アプリ先頭で代替）
WM.on_key(0x0F, [:cmd, :alt]) do                    # R
  (WM.load("layout:#{layout_signature}") || []).each do |s|
    win = WM.windows.find { |w| w["app"] == s["app"] && w["title"] == s["title"] } ||
          WM.windows.find { |w| w["app"] == s["app"] }
    next unless win
    WM.move(win["id"], s["x"], s["y"]); WM.resize(win["id"], s["w"], s["h"])
  end
  true
end

# 接続/切断で自動モード切替（冪等に）
WM.on_screens_changed do |screens|
  # 例: 構成変化時にその構成の保存レイアウトを自動適用するなら、上の復元処理をここで呼ぶ
  warn "screens -> #{screens.size}"
end
```
> **再起動後の復元の流れ**: ログイン項目で WindowManager を起動 → 対象アプリのウィンドウが
> 揃ってから **⌘⌥R を1回**。`CGWindowID` は再起動で変わるので **id では復元できない**点に注意
> （app + title で照合する）。

### リーダーキー / モード（F1 → t で tiling …）

修飾キーを消費せず、**1 つのキーでモードに入り、続く 1 キーで操作**する方式。`on_any_key`
（§2.7）に状態変数を組み合わせるだけ。挙動（実行後に抜ける/留まる、サブモード、which-key、
未割り当てキーの扱い）は **全部この Ruby を書き換えて**自由に決められる。

```ruby
mode = nil   # ローカル変数で状態を持つ（クロージャに捕捉される）

WM.on_any_key do |ev|
  next false unless ev[:key_down]
  kc = ev[:keycode]

  if mode == :leader
    case kc
    when 0x11  # t = 左半分
      id = WM.focused_window; WM.tile(id, 0.0, 0.0, 0.5, 1.0) if id
      mode = nil                       # ← 実行後に抜ける。留めたいならこの行を消すだけ
    when 0x10  # y = 右半分
      id = WM.focused_window; WM.tile(id, 0.5, 0.0, 0.5, 1.0) if id
      mode = nil
    when 0x03  # f = 最大化
      id = WM.focused_window; WM.tile(id, 0.0, 0.0, 1.0, 1.0) if id
      mode = nil
    when 0x35  # Esc = キャンセル
      mode = nil
    else
      mode = nil                       # 未割り当てキーで抜ける（モード中は全キー consume）
    end
    next true                          # モード中はすべて consume（タイプミス漏れ防止）
  end

  # 通常時: F1（修飾なし）でモードに入る
  if kc == 0x7A && ev[:mods] == 0
    mode = :leader
    puts "leader: t=← y=→ f=full  (Esc cancel)"   # which-key は puts でも HUD でも好みで
    next true
  end

  false                                # それ以外は素通し（ショートカット占有ゼロ）
end
```
- 「**F1,t で抜ける版**」「**留まって連打できる版**」は `mode = nil` の有無だけ。
- **サブモード**は `mode = :leader_g` のような別状態にして `case` を増やすだけ。
- 自動タイムアウトは無し（ランタイムにタイマーが無い）。抜けるのは「キー実行」「Esc」「未割り当てキー」。

### ドラッグで snap（端へ吸着 / Windows・Rectangle 風）

`on_any_key` のマウス版 `WM.on_drag_end`（§2.8）。ウィンドウを**ドラッグして離した位置**で
画面端・隅を判定し、`WM.tile` で吸着する。consume しないので通常のドラッグ移動と共存する。

```ruby
EDGE = 24   # 端とみなす余白（pt）

WM.on_drag_end do |ev|
  win = ev[:window]
  x, y = ev[:x], ev[:y]
  # カーソルが乗っているスクリーンを選ぶ
  s = WM.screens.find { |sc| x.between?(sc["x"], sc["x"] + sc["w"]) &&
                             y.between?(sc["y"], sc["y"] + sc["h"]) } || WM.screens.first
  next unless s
  left   = x <= s["x"] + EDGE
  right  = x >= s["x"] + s["w"] - EDGE
  top    = y <= s["y"] + EDGE
  bottom = y >= s["y"] + s["h"] - EDGE

  if top && left      then WM.tile(win, 0.0, 0.0, 0.5, 0.5)   # 左上 1/4
  elsif top && right  then WM.tile(win, 0.5, 0.0, 0.5, 0.5)   # 右上 1/4
  elsif bottom && left  then WM.tile(win, 0.0, 0.5, 0.5, 0.5) # 左下 1/4
  elsif bottom && right then WM.tile(win, 0.5, 0.5, 0.5, 0.5) # 右下 1/4
  elsif left   then WM.tile(win, 0.0, 0.0, 0.5, 1.0)          # 左半分
  elsif right  then WM.tile(win, 0.5, 0.0, 0.5, 1.0)          # 右半分
  elsif top    then WM.tile(win, 0.0, 0.0, 1.0, 1.0)          # 上端 → 最大化
  end
  # どの端でもなければ何もしない（ドロップ位置のまま）
end
```
- ゾーンの形（隅で 1/4、上で最大化…）も `EDGE` も全部この Ruby で自由に変えられる。
- メニューバー/Dock を避けたいなら `visible_x/visible_y/visible_w/visible_h` を使って判定する。

---

## 6. ランタイムの制約（生成時に守ること）

- **Ruby は CRuby 3.3（`ruby+stdlib.wasm`）**。標準ライブラリは使える（`json` は wm.rb が require 済み）。
- **使えない/避けるべきもの**:
  - ネイティブ拡張を持つ gem（`gem install` 不可、C 拡張不可）。pure-Ruby のものを `~/.wmrc.rb` に
    インライン展開するなら可。
  - スレッド/Fiber を使った並行処理、ブロッキング I/O、ネットワーク、子プロセス（`system`/`exec`）は
    基本的に不可・非推奨（WASI 環境のため）。
  - **直接のファイル I/O は不可**（`/rpc` 以外に preopen が無い）。永続化が必要なら
    `WM.save` / `WM.load`（§2.6, ホスト側 JSON ストア）を使う。`/rpc/sock` は**触らない**（RPC 専用）。
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
7. ネットワーク/子プロセス/native gem/スレッドは使わない（§6）。永続化は `WM.save`/`WM.load`、
   直接のファイル I/O はしない。
8. 画面構成の変化に反応するなら `WM.on_screens_changed`（複数回呼ばれうるので**冪等**に）。
9. 失敗は静かに false / nil になる設計。重要な前提は自分でチェックする
   （`WM.focused_window` の nil、`WM.load` の nil、照合に失敗した window など）。

実装の正本は `Sources/WindowManager/Resources/wm.rb`、デフォルト設定例は
`Sources/WindowManager/Resources/default.wmrc.rb`。
