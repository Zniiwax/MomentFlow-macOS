import Carbon.HIToolbox
import Foundation

/// 一个全局快捷键：键码 + 修饰键。
///
/// 做成具名结构而不是一对裸的 UInt32，是因为它要存进设置、要显示成 `⌘⇧R`、
/// 还要在设置界面里被用户改。这三件事都不该散落在各处自己拼。
public struct HotkeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon 的修饰键位：cmdKey / shiftKey / optionKey / controlKey。
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var command: Bool { modifiers & UInt32(cmdKey) != 0 }
    public var shift: Bool { modifiers & UInt32(shiftKey) != 0 }
    public var option: Bool { modifiers & UInt32(optionKey) != 0 }
    public var control: Bool { modifiers & UInt32(controlKey) != 0 }

    /// 至少带一个修饰键。
    ///
    /// 也不允许只有 Shift——那样等于把普通的 `R` 抢走，
    /// 打字都会变成触发录制。
    public var isUsable: Bool {
        guard modifiers != 0 else { return false }
        let nonShift = modifiers & ~UInt32(shiftKey)
        return nonShift != 0
    }

    /// `⌘⇧R` 这种显示形式。顺序按 macOS 的习惯：⌃⌥⇧⌘。
    public var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    /// 存进 UserDefaults 的形式。用字符串是为了 `defaults read` 直接能看懂。
    public var storageValue: String { "\(keyCode)-\(modifiers)" }

    public init?(storageValue: String) {
        let parts = storageValue.split(separator: "-")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1])
        else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// MARK: - 键名

public extension HotkeyCombo {
    /// 出厂默认。
    ///
    /// `⌘⇧5` 是系统截图工具栏占着的（系统级快捷键，不是别的 App 抢注），
    /// 所以采集用 `⌥⌘5`——位置对得上，肌肉记忆接近，也不会打架。
    static let defaultCapture = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_5),
        modifiers: UInt32(cmdKey | optionKey)
    )
    static let defaultQuickRecord = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    static let defaultMarker = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: UInt32(cmdKey | optionKey)
    )

    /// 美式键盘的虚拟键码 → 显示的字符。
    ///
    /// 没用 `UCKeyTranslate` 去查当前键盘布局：那套 API 依赖输入法状态，
    /// 结果不稳定，而快捷键本来就该按物理按键位置来认。
    static func keyName(for keyCode: UInt32) -> String {
        if let name = keyNames[keyCode] { return name }
        return "键\(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2",
        121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
