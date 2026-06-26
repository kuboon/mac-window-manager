#if canImport(AppKit)
import AppKit

/// Ruby に渡すアプリ情報。
struct AppInfo: Codable {
    let pid: pid_t
    let name: String
    let bundleID: String
    let active: Bool
    let hidden: Bool

    enum CodingKeys: String, CodingKey {
        case pid, name, active, hidden
        case bundleID = "bundle_id"
    }
}

/// NSWorkspace / NSRunningApplication のラッパ（Part A の §3）。
enum AppAPI {
    static func listApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            // 通常 UI アプリのみ（バックグラウンドのみのプロセスは除外）。
            guard app.activationPolicy == .regular else { return nil }
            return AppInfo(
                pid: app.processIdentifier,
                name: app.localizedName ?? "",
                bundleID: app.bundleIdentifier ?? "",
                active: app.isActive,
                hidden: app.isHidden
            )
        }
    }

    /// 指定 pid のアプリを前面化する。
    @discardableResult
    static func activate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [])
    }

    @discardableResult
    static func hide(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.hide()
    }
}
#endif
