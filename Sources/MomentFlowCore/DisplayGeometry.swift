import AppKit
import CoreGraphics

/// 输出像素尺寸。
public struct PixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// NSScreen 和 ScreenCaptureKit 之间的坐标换算。
///
/// 这里是整个选区功能最容易出错的地方：`NSScreen` 的原点在左下、y 朝上，
/// 而 `SCStreamConfiguration.sourceRect` 的原点在左上、y 朝下。
///
/// 算错了不会报错、不会崩，只会安静地录到旁边那一块区域——
/// 所以这几个换算写成纯函数，单独测。
public enum DisplayGeometry {

    /// 屏幕缩放（点 → 像素）。Retina 上是 2。
    public static func backingScale(for screen: NSScreen?) -> CGFloat {
        screen?.backingScaleFactor ?? 1
    }

    /// 「屏幕局部坐标（原点左下、点）」→「sourceRect（原点左上、点）」。
    ///
    /// - Parameter rect: 选区在屏幕局部坐标里的位置，原点是该屏幕的左下角。
    /// - Parameter screenHeight: 屏幕的高度，单位点。
    public static func sourceRect(fromLocal rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: screenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// 选区点数 × 缩放 → 输出像素尺寸。
    ///
    /// 一律取偶数：H.264 / HEVC 的编码器对奇数尺寸不友好，
    /// 有些尺寸上会直接写不进去。
    public static func pixelSize(forSourceRect rect: CGRect, scale: CGFloat) -> PixelSize {
        let width = max(2, Int((rect.width * scale).rounded()))
        let height = max(2, Int((rect.height * scale).rounded()))
        return PixelSize(width: width - (width % 2), height: height - (height % 2))
    }

    /// 把选区夹进屏幕范围，太小的直接判为无效。
    ///
    /// 返回 nil 表示「这个选区不能用」，调用方应当忽略这一次拖拽，
    /// 而不是拿一个 1×1 的框去开流。
    public static func clamp(
        _ rect: CGRect,
        within bounds: CGRect,
        minimum: CGFloat = 24
    ) -> CGRect? {
        let standardized = rect.standardized
        let clipped = standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width >= minimum, clipped.height >= minimum else {
            return nil
        }
        return clipped
    }

    /// CoreGraphics 全局坐标 → AppKit 全局坐标。
    ///
    /// 两套坐标原点都在主屏，但一个 y 朝下、一个 y 朝上，需要翻一下。
    /// 窗口列表（CGWindowList）给的是前者，画在屏幕上要用后者。
    public static func appKitRect(fromCoreGraphics rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// AppKit 全局坐标 → 某块屏幕的局部坐标（原点在该屏左下角）。
    public static func localRect(fromAppKit rect: CGRect, screenFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    /// 给录制中的画面算码率。
    ///
    /// 按像素数给：1080p 大约 6 Mbps，4K 封顶 24 Mbps。
    /// 低于 4 Mbps 的话，画面里的暗部会明显发糊。
    public static func bitrate(forPixelSize size: PixelSize) -> Int {
        let pixels = Double(size.width * size.height)
        // 每像素约 3 bit：1080p ≈ 6 Mbps，4K ≈ 24 Mbps（正好顶到上限）。
        // 这个数别凭感觉改，改小了画质会很难看——有测试盯着。
        return Int(min(max(pixels * 3, 4_000_000), 24_000_000))
    }
}

public extension NSScreen {
    /// 这块屏对应的 CoreGraphics 显示器 id。
    ///
    /// 用它把 NSScreen 和 SCDisplay 对上——两者没有直接的对应关系，
    /// 只能靠这个 id 桥接。
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
