import AppKit
import MomentFlowCore
import SwiftUI

/// 那个浮在屏幕下方的小工具栏。
@MainActor
final class CaptureToolbarPanel {

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(coordinator: CaptureCoordinator) {
        let host = NSHostingView(rootView: CaptureToolbarView(coordinator: coordinator))
        host.layoutSubtreeIfNeeded()

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // 要比选区浮层再高一层，否则被它盖住就没法点开始。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.orderFrontRegardless()

        self.panel = panel
        reposition()
        // SwiftUI 的第一轮布局可能还没量准，下一帧再修一次尺寸。
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
            self?.reposition()
        }
    }

    /// 贴到目标屏的底部中间，和系统截图工具的位置一致。
    func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 60
        )
        panel.setFrameOrigin(origin)
    }

    /// 内容变了（比如从选择态切到录制态）之后重新量一次尺寸。
    func resizeToFit() {
        guard let panel, let host = panel.contentView as? NSHostingView<CaptureToolbarView> else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CaptureToolbarView: View {
    @ObservedObject var coordinator: CaptureCoordinator

    var body: some View {
        HStack(spacing: 14) {
            if coordinator.stage == .recording {
                recordingControls
            } else {
                pickerControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12))
        )
        .fixedSize()
    }

    private var pickerControls: some View {
        HStack(spacing: 14) {
            Picker("", selection: $coordinator.mode) {
                ForEach(CaptureCoordinator.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Divider().frame(height: 18)

            Toggle("画面", isOn: $coordinator.media.video)
                .toggleStyle(.checkbox)
            Toggle("系统声音", isOn: $coordinator.media.systemAudio)
                .toggleStyle(.checkbox)
            Toggle("麦克风", isOn: $coordinator.media.microphone)
                .toggleStyle(.checkbox)

            Divider().frame(height: 18)

            Text(coordinator.target?.summary ?? "还没选")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            Button("开始录制") { coordinator.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!coordinator.canStart)

            Button("取消") { coordinator.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var recordingControls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                Text(coordinator.elapsedText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            Text(coordinator.media.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(height: 18)

            Button("停止") { coordinator.stop() }
                .keyboardShortcut(.defaultAction)

            Button("丢弃") { coordinator.discard() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
