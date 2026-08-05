---
title: macOS Window API
parent: 内部資料
nav_order: 1
---

# macOS ウィンドウマネージ API インベントリ

このドキュメントは、本アプリ（Ruby でスクリプタブルな macOS ウィンドウマネージャ）が
利用しうる **OS 提供のウィンドウ管理 API を、パラメタ・必要権限・Ruby への公開可否とともに
網羅的に**リストアップしたものです。

凡例:
- **公開**: Ruby (`WM` モジュール) から呼べるようにする予定の API
- **R/W**: 読み取り専用 (R) か 読み書き/操作 (W) か
- **権限**: 動作に必要な TCC 権限（`AX`=アクセシビリティ, `SR`=画面収録, `IM`=入力監視, `-`=不要）

---

## 1. CoreGraphics Window Services — 全ウィンドウ列挙（読み取り専用）

`import CoreGraphics` / フレームワーク: CoreGraphics

| API | パラメタ | 返り値 / 内容 | R/W | 権限 | 公開 |
|---|---|---|---|---|---|
| `CGWindowListCopyWindowInfo(_:_:)` | `option: CGWindowListOption`, `relativeToWindow: CGWindowID` | ウィンドウ情報 dict の `CFArray?` | R | -（タイトルは SR） | ✅ `WM.windows` |
| `CGRectMakeWithDictionaryRepresentation(_:_:)` | bounds dict, `inout CGRect` | bounds dict → `CGRect` | R | - | 内部 |
| `CGWindowListCreate(_:_:)` | option, relativeToWindow | `CGWindowID` 配列 | R | - | 内部 |
| `CGWindowListCreateImage(_:_:_:_:)` | `CGRect`, option, windowID, `CGWindowImageOption` | `CGImage?`（スクショ） | R | **SR** | 将来 |
| `CGWindowListCreateImageFromArray(_:_:_:)` | `CGRect`, windowID 配列, imageOption | `CGImage?` | R | **SR** | 将来 |

### `CGWindowListOption` の値
`.optionAll` / `.optionOnScreenOnly` / `.optionOnScreenAboveWindow` /
`.optionOnScreenBelowWindow` / `.optionIncludingWindow` / `.excludeDesktopElements`

### `CGWindowListCopyWindowInfo` の dict キー
| キー | 型 | 内容 |
|---|---|---|
| `kCGWindowNumber` | `CGWindowID`(UInt32) | ウィンドウ ID（系全体で一意） |
| `kCGWindowOwnerPID` | `pid_t` | 所有アプリの PID |
| `kCGWindowOwnerName` | String | アプリ名 |
| `kCGWindowName` | String | ウィンドウタイトル（**SR 権限**が無いと空） |
| `kCGWindowBounds` | dict | `{X, Y, Width, Height}`（**top-left 原点**, グローバル座標） |
| `kCGWindowLayer` | Int | ウィンドウレイヤ（0=通常, 大きいほど前面寄り。メニュー/Dock 等は非0） |
| `kCGWindowAlpha` | Float | 不透明度 0.0–1.0 |
| `kCGWindowIsOnscreen` | Bool | 画面表示中か |
| `kCGWindowSharingState` | Int | 共有状態 |
| `kCGWindowStoreType` / `kCGWindowMemoryUsage` | Int | バッキングストア種別 / メモリ使用量 |

> 注意: CGWindowList は **読み取り専用**。位置・サイズの変更はできない（→ Accessibility を使う）。

---

## 2. Accessibility API（AXUIElement）— ウィンドウの読み書き・操作（中核）

`import ApplicationServices`（HIServices）

### 権限・トラスト
| API | パラメタ | 内容 | 権限 |
|---|---|---|---|
| `AXIsProcessTrusted()` | - | アクセシビリティ許可済みか `Bool` | - |
| `AXIsProcessTrustedWithOptions(_:)` | `[kAXTrustedCheckOptionPrompt: true]` | 未許可なら許可ダイアログを促す | - |

### 要素の生成・走査
| API | パラメタ | 返り値 | R/W |
|---|---|---|---|
| `AXUIElementCreateApplication(_:)` | `pid: pid_t` | アプリの `AXUIElement` | R |
| `AXUIElementCreateSystemWide()` | - | システム全体要素 | R |
| `AXUIElementCopyElementAtPosition(_:_:_:_:)` | app, `x: Float`, `y: Float`, `inout AXUIElement?` | 座標下の要素 | R |
| `AXUIElementCopyAttributeNames(_:_:)` | element, `inout CFArray?` | 属性名一覧 | R |
| `AXUIElementCopyAttributeValue(_:_:_:)` | element, `attr: CFString`, `inout CFTypeRef?` | 属性値 | R |
| `AXUIElementIsAttributeSettable(_:_:_:)` | element, attr, `inout DarwinBoolean` | 書込可否 | R |
| `AXUIElementSetAttributeValue(_:_:_:)` | element, attr, `value: CFTypeRef` | 属性を**設定** | **W** |
| `AXUIElementPerformAction(_:_:)` | element, `action: CFString` | アクション実行 | **W** |

### 値の箱（CGPoint/CGSize の AX 表現）
| API | パラメタ | 内容 |
|---|---|---|
| `AXValueCreate(_:_:)` | `AXValueType`(`.cgPoint`/`.cgSize`/`.cgRect`/`.cfRange`), 値ポインタ | `AXValue?` |
| `AXValueGetValue(_:_:_:)` | `AXValue`, type, `inout` 値 | 取り出し |

### アプリレベル属性
| 属性 | 型 | 内容 | settable |
|---|---|---|---|
| `kAXWindowsAttribute` | 配列 | アプリの全ウィンドウ（`AXUIElement`） | R |
| `kAXMainWindowAttribute` | element | メインウィンドウ | R |
| `kAXFocusedWindowAttribute` | element | フォーカス中ウィンドウ | R |
| `kAXFrontmostAttribute` | Bool | アプリが最前面か | W（前面化） |
| `kAXHiddenAttribute` | Bool | アプリが隠れているか | W |

### ウィンドウレベル属性（操作の主役）
| 属性 | 型 | 内容 | settable | 公開 |
|---|---|---|---|---|
| `kAXPositionAttribute` | `CGPoint`(AXValue) | 位置（top-left, グローバル） | ✅ | ✅ `WM.move` |
| `kAXSizeAttribute` | `CGSize`(AXValue) | サイズ | ✅ | ✅ `WM.resize` |
| `kAXTitleAttribute` | String | タイトル | R | ✅ |
| `kAXMinimizedAttribute` | Bool | 最小化状態 | ✅ | ✅ `WM.minimize` |
| `kAXMainAttribute` | Bool | メインウィンドウか | ✅ | ✅ |
| `kAXFocusedAttribute` | Bool | フォーカス | ✅ | ✅ |
| `kAXFullScreenAttribute` | Bool | フルスクリーン（半公式） | ✅ | 将来 |
| `kAXRoleAttribute` / `kAXSubroleAttribute` | String | 役割（`kAXWindowRole`/`kAXStandardWindowSubrole`） | R | 内部フィルタ |
| `kAXCloseButtonAttribute` / `kAXZoomButtonAttribute` / `kAXMinimizeButtonAttribute` | element | ボタン要素（`kAXPressAction` 対象） | R | 将来 |

### ウィンドウアクション
| アクション | 内容 | 公開 |
|---|---|---|
| `kAXRaiseAction` | ウィンドウを前面へ（`WM.focus` の 2 段目） | ✅ `WM.focus` |
| `kAXPressAction` | ボタン押下（閉じる/ズーム等） | 将来 |

### 変更通知（Observer）
| API | パラメタ | 内容 |
|---|---|---|
| `AXObserverCreate(_:_:_:)` | `pid`, callback, `inout AXObserver?` | 監視オブザーバ作成 |
| `AXObserverAddNotification(_:_:_:_:)` | observer, element, `notification: CFString`, refcon | 通知購読 |
| `AXObserverGetRunLoopSource(_:)` | observer | run loop source（要 run loop 登録） |

主な通知: `kAXWindowMovedNotification`, `kAXWindowResizedNotification`,
`kAXFocusedWindowChangedNotification`, `kAXWindowCreatedNotification`,
`kAXUIElementDestroyedNotification`, `kAXApplicationActivatedNotification`

> AX 操作には **アクセシビリティ権限**が必須。`AXError` を必ずチェック（`.success` 以外は失敗）。

### スレッド方針（重要）

AX の各 API は**対象アプリのメインスレッドへの同期 IPC** で実装されている。相手がビジー・
ハング・モーダル表示中だと、呼び出し側が数秒単位でブロックされる。このアプリは
Ruby → fd 3 → `RpcBridge.dispatch` をメインスレッドで同期実行するので、AX をメインスレッドで
直接叩くと**アプリ 1 つのハングでウィンドウマネージャ全体（キーハンドラを含む）が止まる**。

そこで `AXThreadPool`（`Sources/WindowManager/Native/AXThreadPool.swift`）が pid ごとに
RunLoop 付きの専用スレッドを持ち、AX 呼び出しはすべてそこへ投げてタイムアウト付きで待つ。

- 既定 200ms。超えたら `nil` を返し、呼び出し元は「取得できなかった」として扱う。
- 同一 pid の呼び出しはその pid のスレッド上で直列化される（AX の要求順が保たれる）。
- 3 回連続でタイムアウトしたアプリは 25ms の打診に切り替え、応答が戻れば通常運用へ復帰する。

`CGWindowListCopyWindowInfo` は WindowServer との通信でアプリを待たないため、メインスレッドで
呼んでよい（列挙が AX より速いのはこのため）。

### `AXEnhancedUserInterface`

アプリ要素の非公式属性。VoiceOver 等の支援技術が有効なときに立つ。これが立っていると多くの
アプリ（Electron / Chromium / JetBrains 系など）が位置・サイズ変更を**アニメーション付きで
遅延適用**するようになり、直後に読み返した値が要求と食い違う・タイルがガタつく。

`WM.set_frame` は書き込みの間だけこれを `false` にし、**元から立っていた場合のみ**書き込み後に
戻す（支援技術の動作を壊さないため）。yabai をはじめ既存のウィンドウマネージャが同じ回避策を取る。

---

## 3. NSWorkspace / NSRunningApplication — アプリ・プロセス

`import AppKit`

| API | パラメタ | 内容 | R/W | 公開 |
|---|---|---|---|---|
| `NSWorkspace.shared.runningApplications` | - | `[NSRunningApplication]` | R | ✅ `WM.apps` |
| `NSWorkspace.shared.frontmostApplication` | - | 最前面アプリ | R | ✅ |
| `NSWorkspace.shared.menuBarOwningApplication` | - | メニューバー所有アプリ | R | - |
| `NSRunningApplication.processIdentifier` | - | `pid_t` | R | ✅ |
| `NSRunningApplication.bundleIdentifier` / `.localizedName` | - | bundle id / 表示名 | R | ✅ |
| `NSRunningApplication.activate(options:)` | `NSApplication.ActivationOptions` | アプリを前面化 | W | ✅ `WM.activate` |
| `NSRunningApplication.hide()` / `.unhide()` | - | 隠す / 戻す | W | ✅ |
| `NSRunningApplication.isActive` / `.isHidden` | - | 状態 | R | ✅ |
| `NSRunningApplication.terminate()` / `.forceTerminate()` | - | 終了 | W | 将来 |

通知（`NSWorkspace.shared.notificationCenter`）:
`didActivateApplicationNotification`, `didLaunchApplicationNotification`,
`didTerminateApplicationNotification`, `activeSpaceDidChangeNotification`

---

## 4. NSScreen / CoreGraphics Display — ディスプレイ・マルチモニタ

`import AppKit` / `import CoreGraphics`

| API | パラメタ | 内容 | 原点 | 公開 |
|---|---|---|---|---|
| `NSScreen.screens` | - | `[NSScreen]` 全ディスプレイ | - | ✅ `WM.screens` |
| `NSScreen.main` | - | キー画面 | - | ✅ |
| `NSScreen.frame` | - | 画面全体 `CGRect` | **bottom-left** | ✅ |
| `NSScreen.visibleFrame` | - | Dock/メニューバー除外領域 | **bottom-left** | ✅ |
| `NSScreen.backingScaleFactor` | - | Retina 倍率 | - | ✅ |
| `NSScreen.localizedName` | - | ディスプレイ名 | - | ✅ |
| `NSScreen.deviceDescription[.init("NSScreenNumber")]` | - | `CGDirectDisplayID` | - | 内部 |
| `CGMainDisplayID()` | - | メイン display id | - | - |
| `CGGetActiveDisplayList(_:_:_:)` | maxCount, `inout` 配列, `inout` count | アクティブ display 一覧 | - | - |
| `CGDisplayBounds(_:)` | `CGDirectDisplayID` | display の `CGRect` | **top-left** | - |
| `CGDisplayPixelsWide(_:)` / `CGDisplayPixelsHigh(_:)` | display id | ピクセル寸法 | - | - |

> **座標系の注意（最重要）**: AppKit(`NSScreen`/`NSWindow`) は **bottom-left 原点**、
> CoreGraphics/Accessibility(`kAXPosition`/`CGWindowBounds`/`CGDisplayBounds`) は **top-left 原点**。
> Ruby に渡す座標は **top-left に統一**し、変換は `ScreenAPI.swift` の 1 箇所に集約する。

---

## 5. Quartz Event Services / CGEvent — キーイベント捕捉・合成入力

`import CoreGraphics`

### イベントタップ（グローバルにキーを捕捉・握りつぶし可）
| API | パラメタ | 内容 |
|---|---|---|
| `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)` | `tap: CGEventTapLocation`, `place: CGEventTapPlacement`, `options: CGEventTapOptions`, `eventsOfInterest: CGEventMask`, `callback: CGEventTapCallBack`, `userInfo: UnsafeMutableRawPointer?` | `CFMachPort?` |
| `CFMachPortCreateRunLoopSource(_:_:_:)` | allocator, machPort, order | run loop source |
| `CGEvent.tapEnable(tap:enable:)` | machPort, `Bool` | タップ有効/無効（タイムアウト復帰に使う） |

- `tap`: `.cgSessionEventTap` / `.cghidEventTap` / `.cgAnnotatedSessionEventTap`
- `place`: `.headInsertEventTap` / `.tailAppendEventTap`
- `options`: `.defaultTap`(改変・握りつぶし可) / `.listenOnly`(観測のみ)
- `eventsOfInterest`(`CGEventMask` = `1 << CGEventType`): `.keyDown`, `.keyUp`, `.flagsChanged`,
  マウス各種（`.leftMouseDown` 等）

### コールバック内で使う API
| API | 内容 |
|---|---|
| `event.getIntegerValueField(.keyboardEventKeycode)` | 仮想キーコード |
| `event.flags`（`CGEventFlags`） | 修飾キー: `.maskCommand` / `.maskShift` / `.maskAlternate` / `.maskControl` / `.maskSecondaryFn` |
| return `Unmanaged.passUnretained(event)` | イベントを通す |
| return `nil` | **イベントを握りつぶす**（リマップ） |
| 別 event を return | 改変して差し替え |

### 合成入力（イベント発生）
| API | パラメタ | 内容 |
|---|---|---|
| `CGEvent(keyboardEventSource:virtualKey:keyDown:)` | source, `CGKeyCode`, `Bool` | キーイベント生成 |
| `event.post(tap:)` | `CGEventTapLocation` | イベント送出 |
| `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` | … | マウスイベント生成 |
| `CGWarpMouseCursorPosition(_:)` | `CGPoint` | カーソル移動 |

> イベントタップには **アクセシビリティ権限**（キー捕捉では環境により **入力監視**も）が必要。

### 簡易監視（NSEvent, 握りつぶし不可）
| API | 内容 |
|---|---|
| `NSEvent.addGlobalMonitorForEvents(matching:handler:)` | 他アプリのイベント観測のみ（consume 不可） |
| `NSEvent.addLocalMonitorForEvents(matching:handler:)` | 自アプリのみ（consume 可） |

---

## 6. Carbon HotKey — システム全体ホットキー登録（軽量・consume 可）

`import Carbon`

| API | パラメタ | 内容 |
|---|---|---|
| `RegisterEventHotKey(_:_:_:_:_:_:)` | `keyCode: UInt32`, `modifiers: UInt32`, `hotKeyID: EventHotKeyID`, `target: GetApplicationEventTarget()`, `0`, `inout EventHotKeyRef?` | ホットキー登録 |
| `InstallEventHandler(_:_:_:_:_:)` | target, handler, … | 押下ハンドラ |
| `UnregisterEventHotKey(_:)` | `EventHotKeyRef` | 解除 |

> 特定ショートカットだけ拾うならイベントタップより軽量で安全。ただし「全キーの観測」は不可。
> 本アプリでは初期はイベントタップを使い、ホットキー方式は最適化の選択肢として保持。

---

## 7. private API

いずれも Apple 非公開だが、yabai / AeroSpace など主要なウィンドウマネージャが長年利用しており、
**SIP の無効化も特別な entitlement も不要**。宣言は
`Sources/WindowManager/Native/PrivateAPI.swift` に集約している。

### 使っているもの

| シンボル | 用途 | 代替の公開 API |
|---|---|---|
| `_AXUIElementGetWindow` | AX ウィンドウ要素 → `CGWindowID` | 無し（AX と CG を突き合わせる唯一の手段） |
| `_SLPSSetFrontProcessWithOptions` | アプリを前面化（ウィンドウを起点に指定） | `NSRunningApplication.activate`（アプリ単位まで） |
| `SLPSPostEventRecordTo` | 合成クリックを流してキーウィンドウを確定 | 無し |
| `GetProcessForPID` | pid → `ProcessSerialNumber` | 無し（Carbon 由来で Swift 未公開） |

`WM.focus` は `_SLPSSetFrontProcessWithOptions` でアプリを前面化した後、**座標が NaN（コンテンツ外）の
マウス押下/離上イベント**を `SLPSPostEventRecordTo` で直接届ける。WindowServer は「そのウィンドウが
クリックされた」と解釈してキーウィンドウを切り替えるが、座標が実コンテンツ上に無いのでアプリ側の
クリック処理は発火しない。`AXRaise` だけでは「アプリは前面に来たが別のウィンドウがキーのまま」という
取りこぼしが起きるため、この 2 段構えにしている。

イベントレコードのバイト配置は `WindowManagerCore.KeyWindowEventRecord` に純ロジックとして
切り出してあり、Linux 上のユニットテストで固定されている。

> ⚠️ private シンボルは OS アップデートで予告なく壊れうる。`WM.focus` は
> `_SLPSSetFrontProcessWithOptions` が失敗したら `NSRunningApplication.activate` へ落ちる。

### まだ使っていないもの（Spaces / Mission Control）

`SLSMainConnectionID`, `SLSGetActiveSpace`, `SLSCopyManagedDisplaySpaces`,
`SLSCopySpacesForWindows`, `SLSCopyWindowsWithOptionsAndTags`,
`SLSTransactionCreate` / `SLSTransactionMoveWindowWithGroup`, `SLSRegisterNotifyProc` など。
`/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` を `dlopen` + `dlsym` で引く。

これらを入れると「今どの Space か」「この窓はどの Space か」が取れ、複数ウィンドウの移動を
1 コミットにまとめてチラつきを消せる。検討状況は
[OmniWM から借りるもの]({{ '/from-omniwm' | relative_url }}) を参照。

> なお **「窓を別 Space へ移す」API はどこも使っていない**（OmniWM も含む）。仮想ワークスペースは
> 画面外退避で実現するのが現実解。自アプリのウィンドウだけなら公式の
> `NSWindow.collectionBehavior` で代替可。

---

## 8. 権限 / TCC まとめ

| 権限 | 必要な機能 | 確認/要求 API |
|---|---|---|
| アクセシビリティ (AX) | AX でのウィンドウ操作・イベントタップ | `AXIsProcessTrusted()`, `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` |
| 画面収録 (SR) | ウィンドウ**タイトル**取得・スクショ | `CGPreflightScreenCaptureAccess()`, `CGRequestScreenCaptureAccess()` |
| 入力監視 (IM) | 一部のキー監視構成 | `IOHIDCheckAccess(.listenEvent)`, `IOHIDRequestAccess(.listenEvent)` |

- `.app` の `Info.plist` に各 usage 文字列を記載。
- 署名後、「システム設定 > プライバシーとセキュリティ」でユーザが手動許可。
- 権限はバイナリの署名/パスに紐づくため、**再ビルドで剥がれやすい**（安定運用には署名固定が望ましい）。

---

## 公開 API の Ruby 側マッピング（`WM` モジュール, 初期案）

| Ruby 呼び出し | Swift 実装 | 種別 |
|---|---|---|
| `WM.windows` → `[{id:, pid:, app:, title:, x:, y:, w:, h:, on_screen:}]` | CGWindowList + AX 突合 | 取得 |
| `WM.set_frame(window_id, x, y, w, h)` | AX `kAXPositionAttribute` / `kAXSizeAttribute` を 1 往復で設定（`AXEnhancedUserInterface` を退避） | 操作 |
| `WM.move(window_id, x, y)` | AX `kAXPositionAttribute` 設定 | 操作 |
| `WM.resize(window_id, w, h)` | AX `kAXSizeAttribute` 設定 | 操作 |
| `WM.focus(window_id)` | `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` + AX `kAXRaiseAction` | 操作 |
| `WM.minimize(window_id, bool)` | AX `kAXMinimizedAttribute` | 操作 |
| `WM.focused_window` | AX `kAXFocusedWindowAttribute` | 取得 |
| `WM.apps` | NSWorkspace.runningApplications | 取得 |
| `WM.activate(pid)` | NSRunningApplication.activate | 操作 |
| `WM.screens` → `[{x:, y:, w:, h:, visible:{…}, scale:, name:}]` | NSScreen（top-left 変換済み） | 取得 |
| `WM.on_key(keycode, mods) { |ev| … }` | EventTap → Ruby ディスパッチ | ハンドラ |

> 詳細な実行フロー（同期 RPC・キーディスパッチ）は `README.md` のアーキテクチャ節を参照。
