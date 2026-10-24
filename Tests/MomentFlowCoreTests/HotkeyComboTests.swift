import Carbon.HIToolbox
import XCTest
@testable import MomentFlowCore

final class HotkeyComboTests: XCTestCase {

    // MARK: - 显示

    func testDisplayUsesMacSymbolOrder() {
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        // 顺序是 ⌃⌥⇧⌘，和 macOS 菜单里一致。
        XCTAssertEqual(combo.display, "⇧⌘R")
    }

    func testDisplayHandlesAllModifiers() {
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_5),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(combo.display, "⌃⌥⇧⌘5")
    }

    func testDisplayCoversNonLetterKeys() {
        XCTAssertEqual(HotkeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey)).display, "⌘5")
        XCTAssertEqual(HotkeyCombo(keyCode: 49, modifiers: UInt32(cmdKey)).display, "⌘空格")
        XCTAssertEqual(HotkeyCombo(keyCode: 36, modifiers: UInt32(cmdKey)).display, "⌘↩")
        XCTAssertEqual(HotkeyCombo(keyCode: 126, modifiers: UInt32(cmdKey | optionKey)).display, "⌥⌘↑")
    }

    func testUnknownKeyCodeStillRenders() {
        // 不能崩，也不能显示成空白——用户至少要知道自己按了什么。
        XCTAssertEqual(HotkeyCombo(keyCode: 200, modifiers: UInt32(cmdKey)).display, "⌘键200")
    }

    // MARK: - 可用性

    func testComboWithoutModifierIsRejected() {
        XCTAssertFalse(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: 0).isUsable)
    }

    func testShiftOnlyComboIsRejected() {
        // 只带 Shift 等于抢走普通按键，打字都会触发录制。
        XCTAssertFalse(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(shiftKey)).isUsable)
    }

    func testCombosWithRealModifiersAreUsable() {
        XCTAssertTrue(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey)).isUsable)
        XCTAssertTrue(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)).isUsable)
        XCTAssertTrue(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey)).isUsable)
        XCTAssertTrue(HotkeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey)).isUsable)
    }

    // MARK: - 存取

    func testStorageRoundTrip() {
        let combo = HotkeyCombo(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        let restored = HotkeyCombo(storageValue: combo.storageValue)
        XCTAssertEqual(restored, combo)
    }

    func testStorageRejectsGarbage() {
        XCTAssertNil(HotkeyCombo(storageValue: ""))
        XCTAssertNil(HotkeyCombo(storageValue: "abc"))
        XCTAssertNil(HotkeyCombo(storageValue: "15"))
        XCTAssertNil(HotkeyCombo(storageValue: "15-"))
    }

    // MARK: - 默认值

    func testDefaultsAreUsableAndDistinct() {
        let all = [HotkeyCombo.defaultCapture, .defaultQuickRecord, .defaultMarker]
        for combo in all {
            XCTAssertTrue(combo.isUsable, "\(combo.display) 不该被当成可用快捷键")
        }
        // 三个默认值互相不能撞车，否则有一个功能直接无声失效。
        XCTAssertEqual(Set(all).count, 3)
    }

    func testDefaultCaptureAvoidsSystemScreenshotShortcut() {
        // ⌘⇧3/4/5 是系统截图，抢了会打架，所以采集用 ⌥⌘5。
        XCTAssertEqual(HotkeyCombo.defaultCapture.display, "⌥⌘5")
    }
}
