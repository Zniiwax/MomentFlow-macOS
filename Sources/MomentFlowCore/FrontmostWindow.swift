import AppKit
import CoreGraphics
import Foundation

/// 当前前台窗口。
///
/// 窗口标题要读出来，前提是 App 已经有「屏幕录制」权限——这是 macOS 的限制，
/// 没权限时系统会把标题字段直接吞掉（返回 nil）而不是报错。
/// 所以标题为空并不代表代码写错了，先看权限。
public struct FrontmostWindow: Sendable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var processID: pid_t?

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        processID: pid_t? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.processID = processID
    }

    public static func current() -> FrontmostWindow {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostWindow(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: windowTitle(for: app?.processIdentifier),
            processID: app?.processIdentifier
        )
    }

    /// 取该进程最前面那个普通窗口的标题。
    ///
    /// 用 CGWindowList 而不是辅助功能 API：前者只要屏幕录制权限，
    /// 后者要额外的「辅助功能」授权，对只想看剧的人来说太打扰了。
    static func windowTitle(for processID: pid_t?) -> String? {
        guard let processID else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in raw {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == processID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let title = entry[kCGWindowName as String] as? String,
                  !title.isEmpty
            else { continue }
            return title
        }
        return nil
    }
}
