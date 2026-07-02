---
title: アプリのホットキー
parent: レシピ集
nav_order: 10
---

# アプリのホットキー（呼び出し・トグル）

- **⌘⌃F** … Finder へフォーカス
- **⌘⌃T** … ターミナルを**トグル**（前面なら隠す、隠れていれば前面へ）
- **⌘⌃D** … ターミナルを**ドロップダウン風**に（前面化して画面上半分に配置）

「どのアプリでも 1 キーで呼び出す/しまう」ための module。トグルはドロップダウン
ターミナル（iTerm2 の Hotkey Window 風）の代わりになる。

```ruby
module AppKeys
  class << self
    # bundle_id のアプリへフォーカス
    def focus(bundle_id)
      app = find(bundle_id) or return
      WM.activate(app["pid"])
    end

    # 前面なら隠す / それ以外なら前面化（トグル）
    def toggle(bundle_id)
      app = find(bundle_id) or return
      app["active"] ? WM.hide_app(app["pid"]) : WM.activate(app["pid"])
    end

    # トグル + 前面化時に画面上部 fh 分へ配置（ドロップダウン風）
    def dropdown(bundle_id, fh: 0.5)
      app = find(bundle_id) or return
      if app["active"]
        WM.hide_app(app["pid"])
      else
        WM.activate(app["pid"])
        # 直後はまだ窓が列挙に出ないことがある。その場合は配置スキップ（もう一度押せば整う）。
        win = WM.windows.find { |w| w["pid"] == app["pid"] }
        WM.tile(win["id"], 0.0, 0.0, 1.0, fh) if win
      end
    end

    private

    def find(bundle_id)
      WM.apps.find { |a| a["bundle_id"] == bundle_id }
    end
  end
end

WM.on_key(0x03, [:cmd, :ctrl]) { AppKeys.focus("com.apple.finder") }      # ⌘⌃F
WM.on_key(0x11, [:cmd, :ctrl]) { AppKeys.toggle("com.apple.Terminal") }   # ⌘⌃T
WM.on_key(0x02, [:cmd, :ctrl]) { AppKeys.dropdown("com.apple.Terminal") } # ⌘⌃D
```

## bundle_id の調べ方

起動中アプリの一覧は Ruby からそのまま見られる。
[CLI]({{ '/recipes/cli' | relative_url }}) が入っていれば:

```sh
WindowManager eval 'WM.apps.map { |a| a["bundle_id"] }'
```

（例: Safari=`com.apple.Safari`, iTerm2=`com.googlecode.iterm2`, VS Code=`com.microsoft.VSCode`）

## 制約

- **アプリの新規起動はできない**（ランタイムの制約で子プロセスを作れない）。
  対象は起動済みアプリのみ。起動もさせたい場合は Raycast / Spotlight と役割分担するか、
  シェル側で `open -b <bundle_id> && WindowManager eval '...'` のように組み合わせる。

## 関連

- `WM.apps` / `WM.activate` / `WM.hide_app` は [API リファレンス]({{ '/wmrc-guide' | relative_url }}) §2。
