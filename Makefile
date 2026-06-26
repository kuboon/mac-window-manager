# Ruby Window Manager — ビルド & .app バンドル化
#
# 前提: macOS + Xcode/Swift toolchain（.app のビルドは macOS API 依存）。
# ただし `make test` のコア層テストは Linux でも実行可能（WindowManagerCore は Apple 非依存）。
# 事前に Resources/ruby.wasm を配置すること（make fetch-ruby か README 参照）。

APP_NAME    := WindowManager
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
APP_BUNDLE  := $(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
# SPM が生成するリソースバンドル名（<Package>_<Target>.bundle）。
# 注意: 行末コメントは付けないこと。Make は `:=` 値の末尾空白をコメント前まで含めてしまい、
#       パスがズレてバンドルを取りこぼす（過去にこれで .app が ruby.wasm 無しで出荷された）。
RES_BUNDLE  := WindowManager_WindowManager.bundle

# 自分用の adhoc 署名。配布時は Developer ID に置き換える。
CODESIGN_ID ?= -

.PHONY: all build app sign run clean fetch-ruby test

all: app

build:
	swift build -c $(CONFIG)

# SPM のビルド成果物を .app バンドルへ組み立てる
app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp bundle/Info.plist $(CONTENTS)/Info.plist
	cp $(BUILD_DIR)/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	# SPM が同梱したリソースバンドル（ruby.wasm 等）を **Contents/Resources** へ置く
	# （codesign は .app ルート直下の同梱物を許さない＝unsealed contents エラー）。
	# アプリ側は main.swift の resourceBundle リゾルバがここを探す（Bundle.module 非依存）。
	# 見つからなければエラーで停止（ruby.wasm 無しの壊れた .app を出荷しないため）。
	@bundle_src="$(BUILD_DIR)/$(RES_BUNDLE)"; \
	if [ ! -d "$$bundle_src" ]; then \
		bundle_src="$$(swift build -c $(CONFIG) --show-bin-path)/$(RES_BUNDLE)"; \
	fi; \
	if [ ! -d "$$bundle_src" ]; then \
		echo "error: resource bundle '$(RES_BUNDLE)' not found (looked in $(BUILD_DIR) and bin-path)." >&2; \
		echo "       Package.swift の resources 宣言と Resources/ruby.wasm の配置を確認すること。" >&2; \
		exit 1; \
	fi; \
	cp -R "$$bundle_src" "$(CONTENTS)/Resources/"
	# .app 内に実際にバンドルと ruby.wasm が入ったか検証（取りこぼし再発防止）。
	@test -d "$(CONTENTS)/Resources/$(RES_BUNDLE)" \
		|| { echo "error: $(RES_BUNDLE) was not copied into the app" >&2; exit 1; }
	@find "$(CONTENTS)/Resources/$(RES_BUNDLE)" -name ruby.wasm | grep -q . \
		|| { echo "error: ruby.wasm missing inside the app bundle" >&2; exit 1; }
	$(MAKE) sign

sign:
	codesign --force --deep \
		--entitlements bundle/WindowManager.entitlements \
		--sign "$(CODESIGN_ID)" \
		$(APP_BUNDLE)
	@echo "Signed $(APP_BUNDLE) with identity '$(CODESIGN_ID)'"

run: app
	open $(APP_BUNDLE)

# コア層（WindowManagerCore）のユニットテスト。macOS / Linux 双方で実行可能。
# ruby.wasm 未取得でもビルドが通るよう、空のプレースホルダを用意してから実行する。
test:
	@test -f Sources/WindowManager/Resources/ruby.wasm || touch Sources/WindowManager/Resources/ruby.wasm
	swift test

# ruby.wasm（reactor + WIT component の stdlib 同梱ビルド）を npm から取得して Resources/ に配置する。
# 採用ビルドは @ruby/3.x-wasm-wasi の ruby+stdlib.wasm（wm.rb の `require "json"` 等に stdlib が必要）。
# 詳細は docs/ruby-wasm-spike.md §1。
RUBY_WASM_PKG ?= @ruby/3.3-wasm-wasi
RUBY_WASM_DST := Sources/WindowManager/Resources/ruby.wasm
fetch-ruby:
	@mkdir -p $(dir $(RUBY_WASM_DST))
	@echo "Fetching $(RUBY_WASM_PKG) (ruby+stdlib.wasm) from npm ..."
	@TARBALL=$$(curl -fsSL "https://registry.npmjs.org/$(RUBY_WASM_PKG)" \
		| python3 -c "import sys,json;d=json.load(sys.stdin);v=d['dist-tags']['latest'];print(d['versions'][v]['dist']['tarball'])"); \
	echo "  tarball: $$TARBALL"; \
	TMP=$$(mktemp -d); \
	curl -fsSL "$$TARBALL" | tar -xz -C "$$TMP" package/dist/ruby+stdlib.wasm; \
	cp "$$TMP/package/dist/ruby+stdlib.wasm" "$(RUBY_WASM_DST)"; \
	rm -rf "$$TMP"
	@ls -la "$(RUBY_WASM_DST)"

clean:
	rm -rf .build $(APP_BUNDLE)
