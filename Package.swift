// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowManager",
    platforms: [
        // ウィンドウ操作・イベントタップに必要な API は macOS 13+ を想定
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WindowManager", targets: ["WindowManager"])
    ],
    dependencies: [
        // 純 Swift 製 WebAssembly ランタイム（ruby.wasm 作者 kateinoigakukun 製）。
        // バージョンは Mac 上で `swift package resolve` 後に Package.resolved で固定すること。
        .package(url: "https://github.com/swiftwasm/WasmKit.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "WindowManager",
            dependencies: [
                .product(name: "WasmKit", package: "WasmKit"),
                .product(name: "WasmKitWASI", package: "WasmKit")
            ],
            resources: [
                // ruby.wasm 本体とデフォルト設定・Ruby ライブラリをバンドルに同梱。
                // `Resources/ruby.wasm` は別途取得（README 参照, .gitignore 済み）。
                .copy("Resources/ruby.wasm"),
                .copy("Resources/wm.rb"),
                .copy("Resources/default.wmrc.rb")
            ]
        ),
        .testTarget(
            name: "WindowManagerTests",
            dependencies: ["WindowManager"]
        )
    ]
)
