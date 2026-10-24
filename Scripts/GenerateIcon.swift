// 生成 App 图标（矢量绘制 → PNG → .icns）和菜单栏模板图标。
//
// 设计：Big Sur 圆角方底板（深夜靛蓝渐变）+ 一个选取框 + 中间一颗录制红点。
// 「框住一块正在录的区域」是这个 App 唯一的动作，所以图标只讲这一件事，
// 不放任何别的元素——图标越小越要靠单一形状说话。
//
// 小尺寸（≤64px）会自动去掉四角把手并加粗描边，
// 否则缩小之后把手会糊成一圈脏点。
//
// 用法：swift Scripts/GenerateIcon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - 基础工具

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

func linearGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

/// 超椭圆（squircle）：|x/a|^n + |y/b|^n = 1。
/// 用它近似 macOS 的连续圆角——普通圆角矩形在系统里会显得"不够原生"。
func squirclePath(in rect: CGRect, exponent: CGFloat = 5, samples: Int = 1440) -> CGPath {
    let a = rect.width / 2
    let b = rect.height / 2
    let path = CGMutablePath()
    for index in 0...samples {
        let t = CGFloat(index) / CGFloat(samples) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = rect.midX + a * copysign(pow(abs(ct), 2 / exponent), ct)
        let y = rect.midY + b * copysign(pow(abs(st), 2 / exponent), st)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func render(size: CGFloat, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let pixels = Int(size)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    draw(context, size)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "MomentFlowIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "建不了 \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "MomentFlowIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "写不了 \(url.path)"])
    }
}

// MARK: - 图形元素

/// 选取框 + 中间那颗红点。整个图标就靠这一个形状说话。
func drawCaptureMark(
    in context: CGContext,
    size: CGFloat,
    showHandles: Bool,
    lineWidth: CGFloat,
    markWidth: CGFloat,
    markHeight: CGFloat
) {
    let rect = CGRect(
        x: (size - markWidth) / 2,
        y: (size - markHeight) / 2,
        width: markWidth,
        height: markHeight
    )
    let corner = min(markWidth, markHeight) * 0.22
    let frame = CGPath(
        roundedRect: rect,
        cornerWidth: corner,
        cornerHeight: corner,
        transform: nil
    )

    // 红点先画，让它压在框线下面，框线保持干净。
    let dotRadius = min(markWidth, markHeight) * 0.155
    let dotCenter = CGPoint(x: rect.midX, y: rect.midY)

    // 很轻的外发光。给重了会在深色底上糊成一圈脏印子。
    if showHandles, let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(255, 77, 94, 0.30), rgb(255, 77, 94, 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.saveGState()
        context.drawRadialGradient(
            glow,
            startCenter: dotCenter,
            startRadius: dotRadius * 0.9,
            endCenter: dotCenter,
            endRadius: dotRadius * 1.9,
            options: []
        )
        context.restoreGState()
    }

    context.setFillColor(rgb(255, 77, 94))
    context.fillEllipse(in: CGRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))

    context.setStrokeColor(rgb(255, 255, 255, 0.96))
    context.setLineWidth(lineWidth)
    context.setLineJoin(.round)
    context.addPath(frame)
    context.strokePath()

    guard showHandles else { return }

    // 四角把手，和大尺寸的选区浮层是同一套视觉语言。
    // 尺寸刻意压到略大于线宽——做大了会变成四坨，抢掉框和红点的戏。
    let handle = lineWidth * 1.5
    let corners = [
        CGPoint(x: rect.minX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.minY),
        CGPoint(x: rect.minX, y: rect.maxY),
        CGPoint(x: rect.maxX, y: rect.maxY)
    ]
    context.setFillColor(rgb(255, 255, 255))
    for corner in corners {
        let box = CGRect(
            x: corner.x - handle / 2,
            y: corner.y - handle / 2,
            width: handle,
            height: handle
        )
        context.addPath(CGPath(
            roundedRect: box,
            cornerWidth: handle * 0.25,
            cornerHeight: handle * 0.25,
            transform: nil
        ))
    }
    context.fillPath()
}

/// 整枚 App 图标。
func drawAppIcon(in context: CGContext, size: CGFloat) {
    // macOS 图标的画布留白：内容约占 82%，居中。
    let inset = size * 0.09
    let baseRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let base = squirclePath(in: baseRect)

    context.saveGState()
    context.addPath(base)
    context.clip()

    // 深夜靛蓝：上半偏亮，底部压暗。
    let gradient = linearGradient(
        [rgb(74, 78, 146), rgb(38, 42, 82), rgb(24, 26, 50)],
        [0, 0.55, 1]
    )
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: baseRect.midX, y: baseRect.maxY),
        end: CGPoint(x: baseRect.midX, y: baseRect.minY),
        options: []
    )

    // 顶部的柔光，让底板不至于是一块死板的渐变。
    if let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(255, 255, 255, 0.16), rgb(255, 255, 255, 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawRadialGradient(
            sheen,
            startCenter: CGPoint(x: baseRect.midX, y: baseRect.maxY * 1.05),
            startRadius: 0,
            endCenter: CGPoint(x: baseRect.midX, y: baseRect.maxY),
            endRadius: baseRect.width * 0.85,
            options: []
        )
    }
    context.restoreGState()

    // 底色边缘那圈很淡的高光，是 macOS 图标的常见细节。
    context.saveGState()
    context.addPath(base)
    context.clip()
    context.setStrokeColor(rgb(255, 255, 255, 0.14))
    context.setLineWidth(size * 0.008)
    context.addPath(base)
    context.strokePath()
    context.restoreGState()

    let detailed = size >= 128
    drawCaptureMark(
        in: context,
        size: size,
        showHandles: detailed,
        lineWidth: detailed ? size * 0.038 : size * 0.058,
        markWidth: baseRect.width * 0.64,
        markHeight: baseRect.height * 0.50
    )
}

// MARK: - 生成 App 图标

let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    let image = render(size: variant.size) { context, size in
        drawAppIcon(in: context, size: size)
    }
    try writePNG(image, to: iconset.appendingPathComponent(variant.name))
}
print("已生成图标帧：\(iconset.path)")

// MARK: - 菜单栏模板图标

// 菜单栏用单色模板：黑色 + alpha，系统会按深浅色自动反色。
// 尺寸给 18pt @2x = 36px，够 Retina 用。
let menuSize: CGFloat = 36
let menuImage = render(size: menuSize) { context, size in
    context.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)
    context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!)

    // 留白小一点，菜单栏图标要尽量占满可点区域。
    let inset = size * 0.14
    let rect = CGRect(x: inset, y: inset * 1.35, width: size - inset * 2, height: size - inset * 2.7)
    let corner = rect.height * 0.28
    context.setLineWidth(size * 0.075)
    context.setLineJoin(.round)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.strokePath()

    let radius = rect.height * 0.19
    context.fillEllipse(in: CGRect(
        x: rect.midX - radius,
        y: rect.midY - radius,
        width: radius * 2,
        height: radius * 2
    ))
}
try writePNG(menuImage, to: resources.appendingPathComponent("MenuBarIcon.png"))
print("已生成菜单栏模板图标：\(resources.appendingPathComponent("MenuBarIcon.png").path)")

print("下一步：iconutil -c icns \"\(iconset.path)\" -o \"\(resources.appendingPathComponent("AppIcon.icns").path)\"")
