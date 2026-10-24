import AppKit
import SwiftUI

/// 录制完成后右下角滑出来的小提示。
///
/// 三件事：说清楚存到哪了、几秒后自己消失、点一下在访达里定位到文件。
///
/// 做成**非激活**的浮层有两层原因：一是不抢走正在播的视频的焦点，
/// 二是它的窗口层级要能盖住全屏播放的画面——用户多半就是在全屏看片时录的，
/// 提示被压在视频底下就等于没有。
@MainActor
final class SavedToast {

    struct Content {
        var title: String
        var detail: String
        /// 缩写过的文件路径，太长的话界面里放不下。
        var path: String
        /// 点一下要在访达里定位到的文件。
        var fileURL: URL
    }

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    /// 自动消失的时间。鼠标移上去会暂停倒计时。
    private let visibleDuration: TimeInterval = 5

    var isShowing: Bool { panel != nil }

    func show(_ content: Content) {
        dismiss()

        let host = NSHostingView(rootView: SavedToastView(
            content: content,
            onReveal: { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([content.fileURL])
                self?.dismiss()
            },
            onHoverChange: { [weak self] hovering in
                self?.scheduleDismiss(paused: hovering)
            }
        ))
        host.layoutSubtreeIfNeeded()

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // 用和选区浮层一样的层级，确认过能盖在全屏视频上面。
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        self.panel = panel
        position()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        scheduleDismiss(paused: false)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func scheduleDismiss(paused: Bool) {
        dismissWork?.cancel()
        guard !paused else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
    }

    /// 贴到鼠标所在那块屏的右下角，和系统截图的小缩略图位置一致。
    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 20,
            y: visible.minY + 20
        ))
    }
}

private struct SavedToastView: View {
    let content: SavedToast.Content
    let onReveal: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.callout.weight(.medium))
                Text(content.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(content.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("点一下在访达里显示")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12))
        )
        .contentShape(Rectangle())
        .onTapGesture { onReveal() }
        .onHover { onHoverChange($0) }
    }
}
