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
RES_BUNDLE  := WindowManager_WindowManager.bundle   # SPM が生成するリソースバンドル名

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
	# SPM が同梱したリソースバンドル（ruby.wasm 等）を Contents/Resources へ
	@if [ -d "$(BUILD_DIR)/$(RES_BUNDLE)" ]; then \
		cp -R "$(BUILD_DIR)/$(RES_BUNDLE)" "$(CONTENTS)/Resources/"; \
	else \
		echo "warning: resource bundle $(RES_BUNDLE) not found; check Package.swift resources"; \
	fi
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

# ruby.wasm（WASI ビルド）を取得して Resources/ に配置するヘルパ。
# 実際の URL/バージョンは README の指示に従う（@ruby/wasm-wasi のリリース資産）。
fetch-ruby:
	@echo "Place a WASI build of ruby.wasm at Sources/WindowManager/Resources/ruby.wasm"
	@echo "See README.md > 'ruby.wasm の取得' for the exact release asset and unpacking steps."

clean:
	rm -rf .build $(APP_BUNDLE)
