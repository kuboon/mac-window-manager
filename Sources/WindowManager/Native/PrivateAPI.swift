#if canImport(AppKit)
import ApplicationServices
import CoreGraphics
import CoreServices
import Foundation
import WindowManagerCore

// MARK: - private シンボルの宣言
//
// いずれも Apple 非公開だが、yabai / AeroSpace / Rectangle など主要なウィンドウマネージャが
// 長年利用しており、SIP の無効化も特別な entitlement も要らない。
// 公開 API だけでは実現できない 2 点を埋めるために使う:
//   1. CGWindowID ↔ AXUIElement の対応付け（`_AXUIElementGetWindow`）
//   2. 「アプリを前面化しつつ特定ウィンドウをキーウィンドウにする」（`SLPS*`）
//
// 解決方法は所在で分ける:
//   - ApplicationServices / CoreServices に**同梱されている**ものは `@_silgen_name` で宣言する
//     （`_AXUIElementGetWindow` / `GetProcessForPID`）。通常のリンクで解決できる。
//   - SkyLight.framework（private framework）にあるものは `dlopen` + `dlsym` で実行時に引く。
//     こちらを `@_silgen_name` にすると private framework の明示リンクが要るうえ、
//     シンボルが消えた OS では**起動そのものが失敗する**。
// いずれにせよ将来消える可能性はあるので、呼び出し側は失敗を許容できる形にしておくこと。

/// AX ウィンドウ要素から CGWindowID を得る。
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement,
                           _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// pid から ProcessSerialNumber を得る（Carbon 由来。Swift へは公開されていない）。
@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t,
                              _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

/// SkyLight（private framework）のシンボルを実行時に解決する。
///
/// `@_silgen_name` で宣言するとリンク時に SkyLight.framework を明示リンクする必要があり、
/// さらに**シンボルが消えた OS では起動そのものが失敗する**。`dlopen` + `dlsym` なら
/// 解決に失敗しても nil が返るだけなので、呼び出し側が公開 API へフォールバックできる。
private enum SkyLight {

    /// 指定プロセスを前面化する。`windowID` を渡すとそのウィンドウを起点として扱う。
    typealias SetFrontProcessWithOptions =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError

    /// 生のイベントレコードを指定プロセスへ直接届ける。
    typealias PostEventRecordTo =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> CGError

    static let setFrontProcessWithOptions: SetFrontProcessWithOptions? =
        resolve("_SLPSSetFrontProcessWithOptions")

    static let postEventRecordTo: PostEventRecordTo? =
        resolve("SLPSPostEventRecordTo")

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func resolve<T>(_ symbol: String) -> T? {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            NSLog("[wm] SkyLight のシンボル \(symbol) を解決できませんでした")
            return nil
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}

enum PrivateAPI {

    /// `_SLPSSetFrontProcessWithOptions` のモード（Carbon の `kCPSUserGenerated`）:
    /// ユーザ操作由来の前面化として扱わせる。
    private static let userGenerated: UInt32 = 0x200

    /// AX ウィンドウ要素に対応する CGWindowID。取得できなければ nil。
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// 指定ウィンドウへフォーカスを移す。
    ///
    /// `AXRaise` だけでは「アプリは前面に来たが、そのアプリの別のウィンドウがキーのまま」
    /// という取りこぼしが起きる。ここでは
    ///   1. `_SLPSSetFrontProcessWithOptions` でアプリを前面化し
    ///   2. コンテンツ外座標の合成クリックを流してキーウィンドウを確定させる
    /// という 2 段で決める。WindowServer との通信なので**対象アプリの応答を待たない**
    /// （＝ハングしたアプリでもブロックしない）。メインスレッドから呼んでよい。
    ///
    /// `AXRaise` は同一アプリ内の重なり順を整えるために別途 AX スレッドで撃つ（呼び出し側の責務）。
    @discardableResult
    static func focusWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess = SkyLight.setFrontProcessWithOptions else { return false }

        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else { return false }

        // 戻り値は「前面化できたか」だけを見る。合成クリックが弾かれても
        // アプリの前面化自体は済んでいるので、呼び出し側でフォールバックする意味がない。
        guard setFrontProcess(&psn, UInt32(windowID), userGenerated) == .success else {
            return false
        }

        var record = KeyWindowEventRecord.make(windowID: UInt32(windowID), phase: .mouseDown)
        if !post(record, to: &psn) {
            NSLog("[wm] キーウィンドウ確定イベントの送出に失敗しました (window \(windowID))")
        }
        KeyWindowEventRecord.setPhase(.mouseUp, in: &record)
        _ = post(record, to: &psn)
        return true
    }

    private static func post(_ record: [UInt8], to psn: inout ProcessSerialNumber) -> Bool {
        guard let postEventRecord = SkyLight.postEventRecordTo else { return false }
        return record.withUnsafeBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return postEventRecord(&psn, base) == .success
        }
    }
}
#endif
