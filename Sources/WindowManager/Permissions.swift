#if canImport(AppKit)
import ApplicationServices
import AppKit
import CoreGraphics

/// TCC 権限の確認・要求（Part A の §8）。
enum Permissions {
    /// アクセシビリティ権限があるか。無ければ（promptIfNeeded 時）許可ダイアログを促す。
    @discardableResult
    static func ensureAccessibility(promptIfNeeded: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 画面収録権限（ウィンドウタイトル取得に必要）。
    @discardableResult
    static func ensureScreenRecording(requestIfNeeded: Bool = false) -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        if !granted && requestIfNeeded {
            return CGRequestScreenCaptureAccess()
        }
        return granted
    }

    /// 未許可時にユーザへ案内するアラートを表示する。
    static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "アクセシビリティ権限が必要です"
        alert.informativeText = """
        ウィンドウ操作とキーイベント処理のために、
        「システム設定 > プライバシーとセキュリティ > アクセシビリティ」で
        本アプリを許可してください。許可後はアプリを再起動してください。
        """
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "あとで")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
#endif
