import XCTest
@testable import MomentFlowCore

final class LibraryLocationTests: XCTestCase {

    /// 用一个独立的偏好域，别搅到真实 App 的设置。
    private func makeDefaults() -> UserDefaults {
        let suite = "MomentFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultRootIsOnTheDesktop() {
        let root = MomentStore.defaultRoot()
        XCTAssertEqual(root.lastPathComponent, "MomentFlow")
        XCTAssertEqual(root.deletingLastPathComponent().lastPathComponent, "Desktop")
    }

    func testConfiguredRootFallsBackToDefault() {
        let defaults = makeDefaults()
        XCTAssertEqual(MomentStore.configuredRoot(defaults: defaults), MomentStore.defaultRoot())
    }

    func testConfiguredRootWinsWhenSet() {
        let defaults = makeDefaults()
        let custom = URL(fileURLWithPath: "/tmp/somewhere/素材", isDirectory: true)

        MomentStore.setConfiguredRoot(custom, defaults: defaults)
        XCTAssertEqual(MomentStore.configuredRoot(defaults: defaults), custom)
    }

    func testEmptyPathIsIgnored() {
        // 空字符串不该被当成一个有效位置，否则素材库会变成当前目录。
        let defaults = makeDefaults()
        defaults.set("", forKey: MomentStore.rootPreferenceKey)
        XCTAssertEqual(MomentStore.configuredRoot(defaults: defaults), MomentStore.defaultRoot())
    }

    func testResetGoesBackToDefault() {
        let defaults = makeDefaults()
        MomentStore.setConfiguredRoot(URL(fileURLWithPath: "/tmp/x"), defaults: defaults)
        MomentStore.resetConfiguredRoot(defaults: defaults)
        XCTAssertEqual(MomentStore.configuredRoot(defaults: defaults), MomentStore.defaultRoot())
    }
}
