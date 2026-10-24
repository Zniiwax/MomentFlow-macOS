import AppKit
import MomentFlowCore
import SwiftUI

/// 首次启动（以及重新打开 App）时露出来的窗口。
///
/// 没有它的话，这个 App 双击之后什么都不会发生——它是纯菜单栏应用，
/// 不占 Dock、没有主窗口，唯一的存在感是菜单栏右上角一个 18 点的小图标。
/// 用户看到的就是「打不开」。
@MainActor
final class WelcomeWindowController {

    private var window: NSWindow?

    var onGrantScreenRecording: (() -> Void)?
    var onOpenLibrary: (() -> Void)?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = WelcomeView(
            settings: .shared,
            screenGranted: CapturePermission.hasScreenRecording,
            onGrant: { [weak self] in self?.onGrantScreenRecording?() },
            onOpenLibrary: { [weak self] in self?.onOpenLibrary?() },
            onClose: { [weak self] in self?.close() }
        )

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MomentFlow"
        window.contentView = NSHostingView(rootView: view)
        applyContentSize(to: window)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    /// 权限状态变了（比如刚授权完重启），窗口开着的话刷一下内容。
    func refresh() {
        guard let window else { return }
        let view = WelcomeView(
            settings: .shared,
            screenGranted: CapturePermission.hasScreenRecording,
            onGrant: { [weak self] in self?.onGrantScreenRecording?() },
            onOpenLibrary: { [weak self] in self?.onOpenLibrary?() },
            onClose: { [weak self] in self?.close() }
        )
        window.contentView = NSHostingView(rootView: view)
        applyContentSize(to: window)
    }

    func close() {
        window?.close()
        window = nil
    }

    /// SwiftUI 第一次量出来可能是 0，用兜底尺寸顶一下，别开出一个看不见的小窗。
    private func applyContentSize(to window: NSWindow) {
        let measured = window.contentView?.fittingSize ?? .zero
        let size = measured.width > 200 && measured.height > 200
            ? measured
            : NSSize(width: 480, height: 470)
        window.setContentSize(size)
    }
}

private struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    let screenGranted: Bool
    let onGrant: () -> Void
    let onOpenLibrary: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            permission
            Divider()
            shortcuts
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("MomentFlow")
                    .font(.title2.weight(.semibold))
                Text("把看剧、看视频的时间，变成能检索的素材。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("常驻菜单栏，不占 Dock，也不抢焦点。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var permission: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: screenGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(screenGranted ? Color.green : Color.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text(screenGranted ? "屏幕录制权限：已授权" : "还差屏幕录制权限")
                    .font(.callout.weight(.medium))
                if !screenGranted {
                    Text("录制和截图都要这个权限。授权之后必须退出再重新打开本应用才生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("授予屏幕录制权限…") { onGrant() }
                        .controlSize(.small)
                }
            }
            Spacer()
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("三个快捷键")
                .font(.callout.weight(.medium))
            shortcutRow(settings.combo(for: .capture).display, "采集片段：选整屏 / 窗口 / 选区，再决定录画面还是只录声音")
            shortcutRow(settings.combo(for: .quickRecord).display, "快速录制当前窗口，再按一次停")
            shortcutRow(settings.combo(for: .marker).display, "记一个点：截一张图，随手写两句")
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("打开素材库") { onOpenLibrary() }
            Spacer()
            Button("开始使用") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
