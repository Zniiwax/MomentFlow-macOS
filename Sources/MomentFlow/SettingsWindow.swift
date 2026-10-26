import AppKit
import MomentFlowCore
import SwiftUI

@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    var onGrantScreenRecording: (() -> Void)?

    func show(settings: AppSettings) {
        if let window {
            refresh(settings: settings)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MomentFlow 设置"
        window.contentView = NSHostingView(rootView: makeView(settings: settings))
        applyContentSize(to: window)
        window.minSize = NSSize(width: 540, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    /// 权限状态之类的信息可能在窗口关着的时候变了，重新打开时要刷新。
    func refresh(settings: AppSettings) {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: makeView(settings: settings))
        applyContentSize(to: window)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeView(settings: AppSettings) -> SettingsView {
        SettingsView(
            settings: settings,
            screenGranted: CapturePermission.hasScreenRecording,
            onGrant: { [weak self] in self?.onGrantScreenRecording?() }
        )
    }

    private func applyContentSize(to window: NSWindow) {
        let measured = window.contentView?.fittingSize ?? .zero
        // SwiftUI 量出来的尺寸有时会很大或为 0，夹到一个合理的区间里，
        // 免得开出一个占满屏幕或者看不见的窗口。
        let size = NSSize(
            width: min(max(measured.width, 560), 680),
            height: min(max(measured.height, 460), 680)
        )
        window.setContentSize(size)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let screenGranted: Bool
    let onGrant: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hotkeys
                Divider()
                library
                Divider()
                recordingDefaults
                Divider()
                permissions
            }
            .padding(22)
            .frame(width: 560, alignment: .leading)
        }
        .frame(maxHeight: 640)
    }

    // MARK: - 快捷键

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("快捷键")
                Spacer()
                Button("全部恢复默认") { settings.resetAllHotkeys() }
                    .controlSize(.small)
            }

            ForEach(AppSettings.HotkeySlot.allCases) { slot in
                hotkeyRow(slot)
            }

            Text("点一下右边的框，然后按下你想用的组合。至少带一个 ⌘ / ⌥ / ⌃。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func hotkeyRow(_ slot: AppSettings.HotkeySlot) -> some View {
        let combo = settings.combo(for: slot)
        let conflict = settings.conflictingSlot(for: combo, excluding: slot)
        let issue = settings.hotkeyIssues[slot]

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.title).font(.callout.weight(.medium))
                    Text(slot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KeyRecorderField(combo: combo) { settings.setCombo($0, for: slot) }
                    .frame(width: 132, height: 26)
                Button {
                    settings.resetCombo(for: slot)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("恢复默认")
                .disabled(combo == slot.defaultCombo)
            }

            if let conflict {
                warning("和「\(conflict.title)」重复了，只能生效一个。")
            } else if let issue {
                warning(issue)
            }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundStyle(.orange)
        .padding(.leading, 2)
    }

    // MARK: - 素材库

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("素材库位置")
            HStack(spacing: 10) {
                Text(abbreviated(settings.libraryRoot.path))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                Button("更改…") { chooseFolder() }
                Button("在访达中打开") {
                    NSWorkspace.shared.open(settings.libraryRoot)
                }
            }
            Text("每条录制会在里面单独建一个文件夹。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "用这个文件夹"
        panel.message = "选一个文件夹放素材库。"
        panel.directoryURL = settings.libraryRoot.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        settings.setLibraryRoot(url)
    }

    // MARK: - 录制默认项

    private var recordingDefaults: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("录制默认项")
            Text("新一次录制开始时用的勾选状态，之后还能在工具栏里改。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Toggle("画面", isOn: videoBinding)
            Toggle("系统声音", isOn: audioBinding)
            Toggle("麦克风", isOn: microphoneBinding)

            Text("麦克风会单独存成一轨。用蓝牙耳机当麦克风时，系统会把蓝牙切到通话模式，系统声音的音质会一起下降。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !settings.defaultMedia.isValid {
                warning("两个都不选就没东西可录了。")
            }
        }
    }

    private var videoBinding: Binding<Bool> {
        Binding(
            get: { settings.defaultMedia.video },
            set: { settings.setDefaultMedia(
                MediaSelection(
                    video: $0,
                    systemAudio: settings.defaultMedia.systemAudio,
                    microphone: settings.defaultMedia.microphone
                )
            ) }
        )
    }

    private var audioBinding: Binding<Bool> {
        Binding(
            get: { settings.defaultMedia.systemAudio },
            set: { settings.setDefaultMedia(
                MediaSelection(
                    video: settings.defaultMedia.video,
                    systemAudio: $0,
                    microphone: settings.defaultMedia.microphone
                )
            ) }
        )
    }

    private var microphoneBinding: Binding<Bool> {
        Binding(
            get: { settings.defaultMedia.microphone },
            set: { settings.setDefaultMedia(
                MediaSelection(
                    video: settings.defaultMedia.video,
                    systemAudio: settings.defaultMedia.systemAudio,
                    microphone: $0
                )
            ) }
        )
    }

    // MARK: - 权限

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("权限")
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: screenGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(screenGranted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(screenGranted ? "屏幕录制：已授权" : "屏幕录制：还没有授权")
                        .font(.callout)
                    if !screenGranted {
                        Text("截图和录制都要它。授权之后必须退出再重新打开本应用才生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("去授权…") { onGrant() }
                            .controlSize(.small)
                    }
                }
            }
            Text("不需要麦克风权限——这个工具不录麦克风。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 通用

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.headline)
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
