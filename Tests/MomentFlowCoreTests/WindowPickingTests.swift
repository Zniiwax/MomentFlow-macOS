import CoreGraphics
import XCTest
@testable import MomentFlowCore

/// 挑窗口这条逻辑出过一次真实的 bug：全屏的 Chrome 录出来是一条细带。
final class WindowPickingTests: XCTestCase {

    func testFullscreenToolbarStripLosesToContentWindow() {
        // 这是真事：全屏 Chrome 的内容窗口 + 那条标题栏辅助窗口。
        // 辅助窗口排在前面，按"取第一个"就会录到它。
        let strip = CGSize(width: 1920, height: 148)
        let content = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(MomentCapturer.largestIndex(sizes: [strip, content]), 1)
    }

    func testPicksLargestRegardlessOfOrder() {
        let small = CGSize(width: 400, height: 300)
        let big = CGSize(width: 1600, height: 1000)
        XCTAssertEqual(MomentCapturer.largestIndex(sizes: [small, big]), 1)
        XCTAssertEqual(MomentCapturer.largestIndex(sizes: [big, small]), 0)
    }

    func testSmallWindowBeatsWiderStrip() {
        // 关键：宽度更大不等于更该录。面积才是判据。
        // 这条辅助窗口宽 1920，但只有 148 高，总像素仍少于 800×600 的普通窗口。
        let strip = CGSize(width: 1920, height: 148)
        let window = CGSize(width: 800, height: 600)
        XCTAssertEqual(MomentCapturer.largestIndex(sizes: [strip, window]), 1)
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(MomentCapturer.largestIndex(sizes: []))
    }

    func testSingleCandidateIsPicked() {
        XCTAssertEqual(MomentCapturer.largestIndex(sizes: [CGSize(width: 10, height: 10)]), 0)
    }
}
