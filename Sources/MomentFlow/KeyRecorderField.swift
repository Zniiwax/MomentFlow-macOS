import AppKit
import Carbon.HIToolbox
import MomentFlowCore
import SwiftUI

/// 一个「点一下，然后按下你想用的组合」的输入框。
struct KeyRecorderField: NSViewRepresentable {
    let combo: HotkeyCombo
    let onCapture: (HotkeyCombo) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.combo = combo
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: KeyRecorderNSView, context: Context) {
        view.combo = combo
        view.onCapture = onCapture
    }
}

final class KeyRecorderNSView: NSView {

    var combo: HotkeyCombo = .defaultQuickRecord {
        didSet { needsDisplay = true }
    }
    var onCapture: ((HotkeyCombo) -> Void)?

    private var isWaiting = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 26) }

    override func mouseDown(with event: NSEvent) {
        isWaiting = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isWaiting else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    /// 带 ⌘ 的组合不会走 keyDown —— 它们先被当作菜单快捷键派发。
    /// 不实现这个方法的话，用户根本录不到任何 ⌘-开头的快捷键。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isWaiting else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // Esc 用来退出输入状态，不当作一个快捷键录进去。
        if event.keyCode == UInt16(kVK_Escape) {
            isWaiting = false
            window?.makeFirstResponder(nil)
            return
        }

        let captured = HotkeyCombo(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(from: event.modifierFlags)
        )
        guard captured.isUsable else {
            // 只有 Shift 或者干脆没有修饰键：会抢走正常打字，不接受。
            NSSound.beep()
            return
        }

        isWaiting = false
        combo = captured
        onCapture?(captured)
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isWaiting = false
        return super.resignFirstResponder()
    }

    /// AppKit 的修饰键 → Carbon 的位标志。注册和显示都用后者。
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)

        if isWaiting {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        (isWaiting ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isWaiting ? 1.5 : 1
        path.stroke()

        let text = isWaiting ? "按下快捷键…" : combo.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: isWaiting
                ? NSFont.systemFont(ofSize: 11)
                : NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isWaiting ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
