// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowManager",
    platforms: [
        // ウィンドウ操作・イベントタップに必要な API は macOS 13+ を想定。
        // （`platforms` は Apple プラットフォームの下限のみを定義する。Linux では
        //  ホスト向けにビルドされ、コア層 `WindowManagerCore` のみが対象になる。）
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WindowManager", targets: ["WindowManager"]),
        // クロスプラットフォームなコア層（Linux でもビルド/テスト可能）。
        .library(name: "WindowManagerCore", targets: ["WindowManagerCore"])
    ],
    dependencies: [
        // 純 Swift 製 WebAssembly ランタイム（ruby.wasm 作者 kateinoigakukun 製）。
        // バージョンは Mac 上で `swift package resolve` 後に Package.resolved で固定すること。
        .package(url: "https://github.com/swiftwasm/WasmKit.git", from: "0.1.0"),
        // FilePath を提供（WasmKit の parseWasm / WASIBridgeToHost で使用）。macOS のみリンク。
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0")
    ],
    targets: [
        // MARK: - コア層（Apple フレームワーク非依存・プラットフォーム非依存）
        // RPC のフレーミング/ワイヤフォーマット、座標変換の純ロジックを収める。
        // ここに macOS 依存を持ち込まないことで Linux 上で `swift test` できる。
        .target(
            name: "WindowManagerCore"
        ),

        // MARK: - macOS アプリ本体（実行ファイル）
        // 個々のソースは `#if canImport(AppKit)` で囲ってあり、Linux では
        // エントリポイントのスタブのみがビルドされる（パッケージ全体をビルド可能に保つため）。
        .executableTarget(
            name: "WindowManager",
            dependencies: [
                "WindowManagerCore",
                // WasmKit は macOS でのみリンク（Linux ではコア層のテストに不要）。
                .product(name: "WasmKit", package: "WasmKit", condition: .when(platforms: [.macOS])),
                .product(name: "WasmKitWASI", package: "WasmKit", condition: .when(platforms: [.macOS])),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.macOS]))
            ],
            resources: [
                // ruby.wasm 本体とデフォルト設定・Ruby ライブラリをバンドルに同梱。
                // `Resources/ruby.wasm` は別途取得（README 参照, .gitignore 済み）。
                // CI など未取得環境では空のプレースホルダを置いてビルドを通す。
                .copy("Resources/ruby.wasm"),
                .copy("Resources/wm.rb"),
                .copy("Resources/default.wmrc.rb")
            ]
        ),

        // MARK: - テスト（コア層を対象。Linux / macOS 双方で実行可能）
        .testTarget(
            name: "WindowManagerCoreTests",
            dependencies: ["WindowManagerCore"]
        )
    ]
)
