import CoreGraphics
import XCTest
@testable import MomentFlowCore

/// 全屏应用的工具栏辅助窗口会混在窗口列表里，必须能被识别出来。
final class ContentWindowTests: XCTestCase {

    func testFullscreenToolbarStripIsNotContent() {
        // 实测数据：全屏 Chrome 录出来是 1920×148，比例接近 13:1。
        XCTAssertFalse(MomentCapturer.isContentWindow(size: CGSize(width: 1920, height: 148)))
        XCTAssertFalse(MomentCapturer.isContentWindow(size: CGSize(width: 1920, height: 114)))
    }

    func testNormalWindowsAreContent() {
        XCTAssertTrue(MomentCapturer.isContentWindow(size: CGSize(width: 1920, height: 1080)))
        XCTAssertTrue(MomentCapturer.isContentWindow(size: CGSize(width: 1624, height: 986)))
        XCTAssertTrue(MomentCapturer.isContentWindow(size: CGSize(width: 800, height: 600)))
        // 超宽屏显示器本身（21:9 大约是 2.4:1）也要算内容。
        XCTAssertTrue(MomentCapturer.isContentWindow(size: CGSize(width: 3440, height: 1440)))
        // 边角情况：正好 6:1 仍然算内容，只排掉更扁的。
        XCTAssertTrue(MomentCapturer.isContentWindow(size: CGSize(width: 600, height: 100)))
    }

    func testDegenerateSizesAreRejected() {
        XCTAssertFalse(MomentCapturer.isContentWindow(size: .zero))
        XCTAssertFalse(MomentCapturer.isContentWindow(size: CGSize(width: 100, height: 0)))
        XCTAssertFalse(MomentCapturer.isContentWindow(size: CGSize(width: 0, height: 100)))
    }
}
