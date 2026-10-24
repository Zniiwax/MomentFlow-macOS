import AppKit
import SwiftUI

@main
struct MomentFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 纯菜单栏应用，没有主窗口。Settings 只是让 App 协议有个合法 Scene。
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不占 Dock，不抢焦点，就是菜单栏上一个图标。
        NSApp.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        controller.install()
        menuBar = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.shutdown()
    }

    /// 录制中直接退进程的话，AVAssetWriter 还没收尾，录了半天的文件就是坏的。
    /// 所以先拦住退出，把文件写完再真的退。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let menuBar, menuBar.isRecording else { return .terminateNow }
        Task { @MainActor in
            await menuBar.finalizeBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// 双击已经在运行的 App 时，把说明窗口调出来，
    /// 否则用户只会觉得「点了没反应」。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showWelcome()
        return true
    }
}
