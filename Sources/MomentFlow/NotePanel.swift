import AppKit
import SwiftUI

/// 记完点弹出来的小便签。
///
/// 设计上刻意不做「保存」按钮：边看边写，改一个字就落一次盘，关掉窗口就完事。
/// 任何需要多点一下的交互，最后都会变成「算了不记了」。
@MainActor
final class NotePanel {

    private var panel: NSPanel?
    private var onChange: ((String) -> Void)?

    func show(
        header: String,
        subheader: String,
        initialText: String,
        onChange: @escaping (String) -> Void
    ) {
        close()
        self.onChange = onChange

        let view = NoteView(
            header: header,
            subheader: subheader,
            initialText: initialText
        ) { [weak self] text in
            self?.onChange?(text)
        }

        let panel = NSPanel(contentViewController: NSHostingController(rootView: view))
        panel.title = "记一个点"
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 440, height: 280))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onChange = nil
    }
}

private struct NoteView: View {
    let header: String
    let subheader: String
    let onChange: (String) -> Void

    @State private var text: String

    init(
        header: String,
        subheader: String,
        initialText: String,
        onChange: @escaping (String) -> Void
    ) {
        self.header = header
        self.subheader = subheader
        self.onChange = onChange
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subheader)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .onChange(of: text) { _, newValue in
                    onChange(newValue)
                }

            Text("边看边写，自动保存，关掉就能接着看。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 440, height: 280)
    }
}
