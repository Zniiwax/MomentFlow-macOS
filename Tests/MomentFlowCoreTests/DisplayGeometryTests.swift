import XCTest
@testable import MomentFlowCore

/// 坐标换算单独测，因为算错了不会报错、不会崩，
/// 只会安静地录到旁边那一块区域——这种 bug 靠肉眼很难发现。
final class DisplayGeometryTests: XCTestCase {

    // MARK: - 选区：视图坐标 → sourceRect

    func testSourceRectFlipsVerticalAxis() {
        // 屏幕高 800，选区在屏幕底部往上 100 点的位置，高 50。
        let local = CGRect(x: 100, y: 100, width: 200, height: 50)
        let source = DisplayGeometry.sourceRect(fromLocal: local, screenHeight: 800)

        XCTAssertEqual(source.minX, 100)
        XCTAssertEqual(source.width, 200)
        XCTAssertEqual(source.height, 50)
        // 屏幕顶部在 sourceRect 里是 y = 0，所以这块离顶 650 点。
        XCTAssertEqual(source.minY, 650)
    }

    func testSourceRectAtTopOfScreenStartsAtZero() {
        let local = CGRect(x: 0, y: 700, width: 400, height: 100)
        let source = DisplayGeometry.sourceRect(fromLocal: local, screenHeight: 800)
        XCTAssertEqual(source.minY, 0)
    }

    func testSourceRectAtBottomOfScreenSitsAboveTheBottomEdge() {
        let local = CGRect(x: 0, y: 0, width: 400, height: 100)
        let source = DisplayGeometry.sourceRect(fromLocal: local, screenHeight: 800)
        XCTAssertEqual(source.minY, 700)
    }

    // MARK: - 输出像素尺寸

    func testPixelSizeAppliesBackingScale() {
        let size = DisplayGeometry.pixelSize(
            forSourceRect: CGRect(x: 0, y: 0, width: 960, height: 540),
            scale: 2
        )
        XCTAssertEqual(size, PixelSize(width: 1920, height: 1080))
    }

    func testPixelSizeRoundsDownToEven() {
        // 奇数尺寸在 H.264 / HEVC 上容易写不进去，所以一律取偶数。
        let size = DisplayGeometry.pixelSize(
            forSourceRect: CGRect(x: 0, y: 0, width: 101, height: 51),
            scale: 1
        )
        XCTAssertEqual(size.width % 2, 0)
        XCTAssertEqual(size.height % 2, 0)
        XCTAssertEqual(size, PixelSize(width: 100, height: 50))
    }

    func testPixelSizeNeverGoesBelowTwo() {
        let size = DisplayGeometry.pixelSize(
            forSourceRect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
            scale: 1
        )
        XCTAssertEqual(size, PixelSize(width: 2, height: 2))
    }

    // MARK: - 夹取与最小尺寸

    func testClampRejectsTinySelection() {
        XCTAssertNil(DisplayGeometry.clamp(
            CGRect(x: 10, y: 10, width: 5, height: 5),
            within: CGRect(x: 0, y: 0, width: 800, height: 600)
        ))
    }

    func testClampTrimsSelectionToScreen() {
        let clamped = DisplayGeometry.clamp(
            CGRect(x: -50, y: -50, width: 200, height: 200),
            within: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertEqual(clamped, CGRect(x: 0, y: 0, width: 150, height: 150))
    }

    func testClampHandlesInvertedDragRect() {
        // 从右下往左上拖，给出的是负宽高。
        let inverted = CGRect(x: 300, y: 300, width: -100, height: -100)
        XCTAssertEqual(DisplayGeometry.clamp(inverted, within: CGRect(x: 0, y: 0, width: 800, height: 600)),
                       CGRect(x: 200, y: 200, width: 100, height: 100))
    }

    // MARK: - 窗口坐标

    func testAppKitRectConvertsWindowCoordinates() {
        // CGWindowList 给的是「主屏左上为原点、y 朝下」。
        let cg = CGRect(x: 100, y: 50, width: 300, height: 200)
        let appKit = DisplayGeometry.appKitRect(fromCoreGraphics: cg, mainDisplayHeight: 1000)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 750, width: 300, height: 200))
    }

    func testLocalRectOffsetsByScreenOrigin() {
        // 副屏在主屏左边时，AppKit 全局坐标是负的。
        let global = CGRect(x: -1200, y: 200, width: 400, height: 300)
        let local = DisplayGeometry.localRect(
            fromAppKit: global,
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        XCTAssertEqual(local, CGRect(x: 720, y: 200, width: 400, height: 300))
    }

    // MARK: - 码率

    func testBitrateHasFloorAndCeiling() {
        XCTAssertEqual(DisplayGeometry.bitrate(forPixelSize: PixelSize(width: 100, height: 100)), 4_000_000)
        XCTAssertEqual(DisplayGeometry.bitrate(forPixelSize: PixelSize(width: 7680, height: 4320)), 24_000_000)

        // 1080p 落在中间档。
        let hd = DisplayGeometry.bitrate(forPixelSize: PixelSize(width: 1920, height: 1080))
        XCTAssertGreaterThan(hd, 4_000_000)
        XCTAssertLessThan(hd, 24_000_000)
    }
}
