---
title: OmniWM から借りるもの
parent: 内部資料
nav_order: 3
---

# OmniWM から借りるもの

[OmniWM](https://github.com/BarutSRB/OmniWM) は Niri / Hyprland に影響を受けた macOS 向けの
タイリングウィンドウマネージャ。Swift 単体で 12 万行を超える大規模な実装で、SkyLight の
private API を使い込んでいる。

このページは「あの規模を真似する」ためのものではなく、**うちの設計（薄い Swift プリミティブ +
Ruby でポリシーを書く）に持ち込む価値がある技術要素**を仕分けした記録。

## 大前提: ライセンス

**OmniWM は GPL-2.0-only**。このリポジトリは MIT なので、**コードをそのまま持ち込むことはできない**。
ここで取り込むのは設計上の知見と、public API では代替できない private シンボルの存在という
**事実**に限る。private API の使い方そのものは MIT の
[yabai](https://github.com/koekeishiya/yabai) が長年公開している内容と同じで、実装は自前で書いている。

## 取り込み済み

| 要素 | 効果 | 実装 |
|---|---|---|
| **アプリごとの AX 専用スレッド + タイムアウト** | 1 つのアプリがハングしてもウィンドウマネージャ全体が止まらない | `Native/AXThreadPool.swift` |
| **`AXEnhancedUserInterface` の退避** | Electron / Chromium / JetBrains 系のリサイズが遅延・アニメーションしなくなる | `WindowAPI.withEnhancedUIDisabled` |
| **`set_frame`（1 往復・移動→リサイズ→再移動・実測値を返す）** | レイアウト敷き直しが速くなり、ディスプレイ境界での押し戻しを吸収できる | `WM.set_frame` |
| **`SLPS` 経由のフォーカス** | 「アプリは前面に来たが別のウィンドウがキーのまま」という取りこぼしが消える | `Native/PrivateAPI.swift` / `WM.focus` |

詳細は [API リファレンス §2.2]({{ '/wmrc-guide#22-操作副作用' | relative_url }}) と
[macOS ウィンドウ API §2 / §7]({{ '/macos-window-api' | relative_url }}) を参照。

## 次に取り込む候補

### SkyLight の読み取り系（Spaces / 高速な全窓列挙）

`/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` を `dlopen` + `dlsym` で引く。
**SIP の無効化も特別な entitlement も要らない。**

| シンボル | 取れるもの | 今の代替 |
|---|---|---|
| `SLSGetActiveSpace` | 今アクティブな Space ID | 無し（切り替わった事実しか分からない） |
| `SLSCopyManagedDisplaySpaces` | ディスプレイごとの Space 一覧と所属ウィンドウ | 無し |
| `SLSCopySpacesForWindows` | ウィンドウ → 所属 Space | 無し |
| `SLSCopyWindowsWithOptionsAndTags` + `SLSWindowIterator*` | 全窓を pid / bounds / level / tags まで一括取得 | `CGWindowList` + AX 突合（重い） |

これが入ると `WM.on_space_changed` が「**どの** Space か」を渡せるようになり、
Space ごとにレイアウトを切り替えるレシピが書けるようになる。

シンボルは `resolve`（必須）と `resolveOptional`（欠けたら機能を落とす）に分けて解決し、
OS 更新でシンボルが消えても起動はできる形にするのが望ましい。

### SkyLight のトランザクション（複数ウィンドウの一括移動）

`SLSTransactionCreate` → `SLSTransactionMoveWindowWithGroup` を必要な数だけ →
`SLSTransactionCommit`。BSP やタイルの敷き直しで**ウィンドウが 1 枚ずつ動くガタつきが消える**。
`WM.batch_move([[id, x, y], ...])` のような形で Ruby へ出す。

> ただし移動できるのは位置のみ（サイズは AX が要る）。「AX でサイズ、SkyLight で位置」の
> 組み合わせになる。

### ウィンドウの生成 / 破棄 / フォーカス変更フック

`AXObserver`（`kAXWindowCreatedNotification` 等）か `SLSRegisterNotifyProc` で受ける。
`WM.on_window_added` / `on_window_closed` / `on_focus_changed` を出せば、
**app rules**（bundle id / タイトル正規表現 → floating / ワークスペース割り当て）や
自動タイリングが Ruby だけで書けるようになる。

⚠️ **同時にエコー判定が要る。** `WM.move` した結果として macOS が返すイベントを
ユーザー操作と誤認すると「retile → move イベント → retile」の無限ループになる。
OmniWM は `IntentLedger` という台帳で「自分が出した要求の反響（echo）」と
「外から来た変化（external）」を分類している。フックを足すときは同時に入れること。

### その他

- **Niri 風スクロール列レイアウト** — 本質は「列の配列 + ビューポートの x オフセット」だけなので、
  アニメーションを捨てれば `WM.set_frame` の上に Ruby のレシピとして書ける。Swift 変更は不要。
- **Caps Lock → F18（Hyper キー）** — 中身は `hidutil` の `UserKeyMapping` を書き換えるだけ。
  ruby.wasm からは子プロセスを起動できないので Swift 側に小さなプリミティブが要る。
- **フォーカス枠** — `SLSNewWindow` でサーバ側に描くのが軽い。`NSWindow` オーバーレイでも可。

## 取り込まないもの

- **4 ステージパイプライン一式**（Intake → World → Effector → Surface、single writer、invariants、
  trace リング）。12 万行を捌くための構造で、うちの規模には過剰。ただし
  **レイアウトエンジンを純関数にする**（`layout(windows, screen) -> {id => rect}` を返し、
  ウィンドウには触らない）という分離だけは Ruby のレシピ側に持ち込む価値がある。
- **Quake ターミナル（Ghostty 組み込み）・コマンドパレット・クリップボード履歴**。
  ウィンドウマネージャの仕事ではない。うちは
  [CLI 制御ソケット]({{ '/recipes/cli' | relative_url }})があるので、Raycast / Alfred から
  `wmrc eval '...'` を叩けば足りる。
- **Overview（サムネイル付き Exposé）**。ScreenCaptureKit が必要でコストが大きい。
- **`omniwmctl` 相当の固定コマンド群**。うちの `wmrc eval` は**任意の Ruby を同じ VM 上で
  実行できる**ので、表現力ではこちらが上。

## OmniWM を読んで分かった「やらなくていいこと」

**「ウィンドウを別の Space へ移す」private API は OmniWM も使っていない**（読み取り系のみ）。
ワークスペースは `SideHiding` — つまり**画面外への退避**で実現している。
うちの [仮想ワークスペース]({{ '/recipes/workspaces' | relative_url }})が採っている方式と同じで、
AeroSpace も同様。この割り切りは正しい。
