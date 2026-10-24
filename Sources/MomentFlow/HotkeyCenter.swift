import Carbon.HIToolbox
import Foundation
import MomentFlowCore

/// 全局快捷键。
///
/// 用 Carbon 的 `RegisterEventHotKey`，而不是 `NSEvent` 的全局监听：
/// 后者需要用户额外授予「辅助功能」权限，前者不需要。
/// 对一个只想随手按一下就记点的小工具来说，少要一个权限差别很大。
final class HotkeyCenter {

    static let shared = HotkeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {
        installHandler()
    }

    /// 注册一个全局快捷键，返回热键 id；注册失败（比如被别的 App 占了）返回 nil。
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return nil }

        handlers[id] = handler
        references.append(reference)
        return id
    }

    @discardableResult
    func register(_ combo: HotkeyCombo, handler: @escaping () -> Void) -> UInt32? {
        register(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: handler)
    }

    /// 撤掉全部注册。
    ///
    /// 用户改了快捷键之后是整组重注册，而不是逐个替换——
    /// 逐个替换很容易在"新组合和旧的撞了"这种顺序问题上留下半死不活的状态。
    func unregisterAll() {
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private static let signature: OSType = {
        // 'MFLW'
        let bytes: [UInt8] = [0x4D, 0x46, 0x4C, 0x57]
        return bytes.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // 这个回调必须是 C 函数指针，不能捕获上下文，所以走单例。
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                HotkeyCenter.shared.fire(hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }
}
