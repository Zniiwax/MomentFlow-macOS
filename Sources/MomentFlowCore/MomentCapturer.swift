import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// 抓一张「我正在看的东西」的截图。
///
/// 优先只抓前台窗口，而不是整屏：桌面图标、聊天窗口弹窗都不该混进素材里。
/// 前台是桌面或者拿不到窗口时，退化成整屏。
public struct MomentCapturer: Sendable {

    public enum CaptureError: LocalizedError {
        case noDisplay
        case encodeFailed

        public var errorDescription: String? {
            switch self {
            case .noDisplay: return "找不到可截取的屏幕"
            case .encodeFailed: return "截图编码失败"
            }
        }
    }

    public init() {}

    public func captureScreenshot() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let front = FrontmostWindow.current()

        if let window = Self.frontmostWindow(in: content, processID: front.processID) {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            // 去掉窗口外面那圈阴影，否则截图右边和下面会多一条灰边。
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return try Self.pngData(from: image)
        }

        guard let display = Self.mainDisplay(in: content) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return try Self.pngData(from: image)
    }

    // MARK: - 内部

    /// 取该进程最像"内容"的那个窗口。
    ///
    /// 不能取列表里的第一个。App 一进全屏，macOS 会把它拆成两个窗口：
    /// 内容窗口，和一条专门放标题栏 / 工具栏的辅助窗口（鼠标移到屏幕顶端时
    /// 滑下来的那条，又宽又扁，通常是整屏宽 × 一百多点高）。
    /// 列表里第一个经常是那条辅助窗口——录出来就是一条横贯屏幕的细带。
    ///
    /// 所以按面积挑最大的：内容窗口永远比工具栏条大得多。
    public static func frontmostWindow(in content: SCShareableContent, processID: pid_t?) -> SCWindow? {
        guard let processID else { return nil }
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == processID
                && window.windowLayer == 0
                && window.isOnScreen
                && window.frame.width > 100
                && window.frame.height > 100
        }
        // 先只在"像内容窗口"的那些里挑；万一一个都不像（比如用户就开了个
        // 特别扁的小窗口），再退回全部，别把选择变成空。
        let contentOnly = candidates.filter { isContentWindow(size: $0.frame.size) }
        return largest(of: contentOnly.isEmpty ? candidates : contentOnly)
    }

    /// 挑面积最大的那个。
    ///
    /// 抽成只看尺寸的纯函数，是因为真正的挑窗口逻辑没法在测试里构造 SCWindow。
    public static func largest(of windows: [SCWindow]) -> SCWindow? {
        let index = largestIndex(sizes: windows.map(\.frame.size))
        return index.map { windows[$0] }
    }

    /// 面积最大的下标。空数组返回 nil。
    static func largestIndex(sizes: [CGSize]) -> Int? {
        sizes.enumerated()
            .max { $0.element.width * $0.element.height < $1.element.width * $1.element.height }?
            .offset
    }

    /// 这个尺寸像不像"用户真正想录的内容窗口"。
    ///
    /// 判据是长宽比。全屏 App 会额外挂一条放标题栏 / 工具栏的辅助窗口，
    /// 它横跨整屏但只有一百多点高，例如 1920×148，比例接近 13:1。
    /// 正常窗口不会长这样，所以比例超过 6:1 的一律当成辅助窗口排掉。
    public static func isContentWindow(size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return size.width / size.height <= 6
    }

    static func mainDisplay(in content: SCShareableContent) -> SCDisplay? {
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }

    static func pngData(from image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        return data
    }
}
