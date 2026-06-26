// swift-tools-version:5.9
import PackageDescription

// 検証用スパイク（本体ビルドからは独立）。
// ruby.wasm が WasmKit（純 Swift の Wasm ランタイム）上で起動し、Ruby を
// 動的 eval できることを Linux/macOS 双方で確認するための最小実行ファイル。
//
// 通常環境では下記 URL 依存がそのまま解決される。git clone がプロキシで
// 遮断される環境（このリポジトリの web セッション等）では README の
// 「ベンダリング手順」を参照（SWIFTCI_USE_LOCAL_DEPS 経由でローカル path 依存に差し替え）。
let package = Package(
    name: "rbexp",
    dependencies: [
        .package(url: "https://github.com/swiftwasm/WasmKit.git", exact: "0.2.2"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "rbexp",
            dependencies: [
                .product(name: "WasmKit", package: "WasmKit"),
                .product(name: "WasmKitWASI", package: "WasmKit"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),
        // fd ベース RPC ラウンドトリップ（Ruby⇄Swift）の de-risk。
        .executableTarget(
            name: "rbrpc",
            dependencies: [
                .product(name: "WasmKit", package: "WasmKit"),
                .product(name: "WasmKitWASI", package: "WasmKit"),
                .product(name: "SystemPackage", package: "swift-system")
            ]
        )
    ]
)
