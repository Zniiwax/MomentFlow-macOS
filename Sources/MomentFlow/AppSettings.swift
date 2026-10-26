import Foundation
import MomentFlowCore

/// 应用设置的唯一来源。
///
/// 快捷键、素材库位置、录制默认项都从这里读写。集中在一个对象里而不是
/// 各处自己去读 UserDefaults，是为了让设置界面改完之后，行为立刻跟着变。
@MainActor
final class AppSettings: ObservableObject {

    enum HotkeySlot: String, CaseIterable, Identifiable {
        case capture
        case quickRecord
        case marker

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capture: return "采集片段"
            case .quickRecord: return "快速录制"
            case .marker: return "记一个点"
            }
        }

        var detail: String {
            switch self {
            case .capture: return "打开工具栏，选整屏 / 窗口 / 选区"
            case .quickRecord: return "直接录当前窗口，再按一次停"
            case .marker: return "截一张图，随手写两句"
            }
        }

        var defaultCombo: HotkeyCombo {
            switch self {
            case .capture: return .defaultCapture
            case .quickRecord: return .defaultQuickRecord
            case .marker: return .defaultMarker
            }
        }
    }

    static let shared = AppSettings()

    @Published private(set) var combos: [HotkeySlot: HotkeyCombo]
    @Published private(set) var libraryRoot: URL
    @Published private(set) var defaultMedia: MediaSelection
    /// 注册失败的组合，界面上直接标出来。
    @Published var hotkeyIssues: [HotkeySlot: String] = [:]

    /// 改完快捷键后通知外面重新注册。
    var onHotkeysChanged: (() -> Void)?
    /// 换素材库位置后通知外面刷新。
    var onLibraryRootChanged: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var combos: [HotkeySlot: HotkeyCombo] = [:]
        for slot in HotkeySlot.allCases {
            let stored = defaults.string(forKey: Self.hotkeyKey(slot))
            combos[slot] = stored.flatMap(HotkeyCombo.init(storageValue:)) ?? slot.defaultCombo
        }
        self.combos = combos

        self.libraryRoot = MomentStore.configuredRoot(defaults: defaults)

        let hasVideo = defaults.object(forKey: Self.videoKey) as? Bool ?? true
        let hasAudio = defaults.object(forKey: Self.audioKey) as? Bool ?? true
        let hasMicrophone = defaults.object(forKey: Self.microphoneKey) as? Bool ?? false
        self.defaultMedia = MediaSelection(
            video: hasVideo,
            systemAudio: hasAudio,
            microphone: hasMicrophone
        )
    }

    // MARK: - 快捷键

    func combo(for slot: HotkeySlot) -> HotkeyCombo {
        combos[slot] ?? slot.defaultCombo
    }

    /// 这个组合是不是已经被别的槽位占了。同一次改动里撞车要当场拦住。
    func conflictingSlot(for candidate: HotkeyCombo, excluding slot: HotkeySlot) -> HotkeySlot? {
        HotkeySlot.allCases.first { $0 != slot && combo(for: $0) == candidate }
    }

    func setCombo(_ combo: HotkeyCombo, for slot: HotkeySlot) {
        guard combo != combos[slot] else { return }
        combos[slot] = combo
        defaults.set(combo.storageValue, forKey: Self.hotkeyKey(slot))
        hotkeyIssues[slot] = nil
        onHotkeysChanged?()
    }

    func resetCombo(for slot: HotkeySlot) {
        setCombo(slot.defaultCombo, for: slot)
    }

    func resetAllHotkeys() {
        for slot in HotkeySlot.allCases {
            combos[slot] = slot.defaultCombo
            defaults.set(slot.defaultCombo.storageValue, forKey: Self.hotkeyKey(slot))
        }
        hotkeyIssues.removeAll()
        onHotkeysChanged?()
    }

    // MARK: - 素材库

    func setLibraryRoot(_ url: URL) {
        guard url != libraryRoot else { return }
        libraryRoot = url
        MomentStore.setConfiguredRoot(url, defaults: defaults)
        onLibraryRootChanged?()
    }

    func resetLibraryRoot() {
        defaults.removeObject(forKey: MomentStore.rootPreferenceKey)
        libraryRoot = MomentStore.defaultRoot()
        onLibraryRootChanged?()
    }

    // MARK: - 录制默认项

    func setDefaultMedia(_ media: MediaSelection) {
        guard media != defaultMedia else { return }
        defaultMedia = media
        defaults.set(media.video, forKey: Self.videoKey)
        defaults.set(media.systemAudio, forKey: Self.audioKey)
        defaults.set(media.microphone, forKey: Self.microphoneKey)
    }

    // MARK: - 键名

    private static let videoKey = "capture.media.video"
    private static let audioKey = "capture.media.audio"
    private static let microphoneKey = "capture.media.microphone"

    private static func hotkeyKey(_ slot: HotkeySlot) -> String {
        "hotkey.\(slot.rawValue)"
    }
}
