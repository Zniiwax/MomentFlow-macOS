import AppKit
import MomentFlowCore
import ScreenCaptureKit

/// 选出来的录制范围。
enum SelectionTarget: Equatable {
    /// 一整块屏幕。
    case display(SCDisplay)
    /// 屏幕上一块矩形。`sourceRect` 是 ScreenCaptureKit 口径（原点左上、单位点）。
    case region(display: SCDisplay, sourceRect: CGRect, pixelSize: PixelSize)
    case window(SCWindow)

    static func == (lhs: SelectionTarget, rhs: SelectionTarget) -> Bool {
        switch (lhs, rhs) {
        case let (.display(lDisplay), .display(rDisplay)):
            return lDisplay.displayID == rDisplay.displayID
        case let (.region(lDisplay, lRect, _), .region(rDisplay, rRect, _)):
            return lDisplay.displayID == rDisplay.displayID && lRect == rRect
        case let (.window(lWindow), .window(rWindow)):
            return lWindow.windowID == rWindow.windowID
        default:
            return false
        }
    }

    /// 界面上给用户看的一句话。
    var summary: String {
        switch self {
        case .display(let display):
            return "整块屏幕 \(display.width) × \(display.height)"
        case .region(_, _, let pixelSize):
            return "选区 \(pixelSize.width) × \(pixelSize.height)"
        case .window(let window):
            return window.title.map { "窗口：\($0)" } ?? "窗口：\(window.owningApplication?.applicationName ?? "未命名")"
        }
    }
}

/// 选区浮层。
///
/// 模仿系统截图的行为，但多给一步：拖完松手之后选区**仍然可以改**——
/// 拖边角调整、拖中间移动，按回车或点工具栏的开始才真正开录。
///
/// 系统自带的 `⇧⌘5` 是「松手即录」，精调只能在截图模式里做。
/// 既然要精度，这里就统一成「松手还能改」。
enum SelectionMode {
    case region
    case window
}

@MainActor
final class SelectionOverlayController {

    /// 目标变化（拖拽中、调整中都会回调）。
    var onUpdate: ((SelectionTarget?) -> Void)?
    /// 按了回车。
    var onConfirm: (() -> Void)?
    /// 按了 Esc。
    var onCancel: (() -> Void)?

    private var windows: [SelectionWindow] = []
    private var candidateWindows: [SCWindow] = []
    private var mode: SelectionMode = .region

    var isPresenting: Bool { !windows.isEmpty }

    /// 弹出浮层开始选。
    ///
    /// - Parameter mode: 选区（拖矩形）或窗口（悬停高亮）。
    func begin(mode: SelectionMode, content: SCShareableContent?) {
        dismiss()
        self.mode = mode
        candidateWindows = Self.buildCandidates(content)

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            view.screenHeight = screen.frame.height
            view.imageScale = screen.backingScaleFactor
            view.cacheDisplays(content)
            view.onUpdate = { [weak self] target in
                self?.onUpdate?(target)
            }
            view.onConfirm = { [weak self] in self?.onConfirm?() }
            view.onCancel = { [weak self] in self?.onCancel?() }
            view.windowCandidates = { [weak self] screen in
                self?.candidateRects(on: screen) ?? []
            }
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }

        // 让用户能直接按 Esc / 回车：非激活面板也能成为 key window，
        // 所以不会把正在播的视频踢出全屏。
        if let key = keyWindowForCursor() {
            key.makeKey()
            // 还要显式把选区视图设成第一响应者。只 makeKey 的话，
            // 键盘事件可能根本到不了它，Esc / 回车就成了摆设。
            if let view = key.contentView {
                key.makeFirstResponder(view)
            }
        }
    }

    /// 鼠标在哪块屏上，就让哪块屏的浮层接键盘。
    private func keyWindowForCursor() -> SelectionWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first { $0.frame.contains(mouse) } ?? windows.first
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        candidateWindows.removeAll()
    }

    /// 屏幕 → 该屏上所有候选窗口的局部矩形。
    private func candidateRects(on screen: NSScreen) -> [(SCWindow, CGRect)] {
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return candidateWindows.compactMap { window in
            let appKit = DisplayGeometry.appKitRect(
                fromCoreGraphics: window.frame,
                mainDisplayHeight: mainHeight
            )
            let local = DisplayGeometry.localRect(fromAppKit: appKit, screenFrame: screen.frame)
            let clipped = local.intersection(CGRect(origin: .zero, size: screen.frame.size))
            guard !clipped.isNull, clipped.width > 40, clipped.height > 40 else { return nil }
            return (window, clipped)
        }
    }

    private static func buildCandidates(_ content: SCShareableContent?) -> [SCWindow] {
        guard let content else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { window in
            // 排掉自己的窗口、桌面、状态栏这些非内容窗口。
            guard window.owningApplication?.processID != ownPID,
                  window.windowLayer == 0,
                  window.isOnScreen,
                  window.frame.width > 80,
                  window.frame.height > 80,
                  // 全屏 App 那条放标题栏的辅助窗口也在这里面。
                  // 不排掉的话，鼠标移到屏幕顶端就会高亮它，点下去就录错了。
                  MomentCapturer.isContentWindow(size: window.frame.size)
            else { return nil }
            return window
        }
    }
}

/// 覆盖一整块屏幕的浮层窗口。
private final class SelectionWindow: NSPanel {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isFloatingPanel = true
        hidesOnDeactivate = false
        // 这几项让它能盖在全屏播放的视频上面。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // 不抢 App 的激活状态，但能拿到键盘事件（Esc / 回车）。
        becomesKeyOnlyIfNeeded = false
        // 窗口模式下要跟着鼠标高亮，所以必须收 mouseMoved。
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 真正负责画和收鼠标键盘的视图。
private final class SelectionView: NSView {

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    var mode: SelectionMode = .region
    var screenHeight: CGFloat = 0
    var imageScale: CGFloat = 1

    var onUpdate: ((SelectionTarget?) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var windowCandidates: ((NSScreen) -> [(SCWindow, CGRect)])?

    private var selection: CGRect?
    private var hoveredWindow: SCWindow?
    private var hoveredRect: CGRect?

    private var activeHandle: Handle?
    private var dragAnchor: CGPoint?
    private var moveGrabOffset: CGSize?
    private var didDrag = false

    private let handleSize: CGFloat = 8
    private let handleHitSlop: CGFloat = 6
    private let minimumSize: CGFloat = 24

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: mode == .region ? .crosshair : .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if mode == .window {
            if let window = hoveredWindow {
                onUpdate?(.window(window))
                onConfirm?()
            }
            return
        }

        didDrag = false

        if let selection {
            if let handle = handle(at: point, in: selection) {
                activeHandle = handle
                dragAnchor = point
                return
            }
            if selection.contains(point) {
                moveGrabOffset = CGSize(
                    width: point.x - selection.minX,
                    height: point.y - selection.minY
                )
                return
            }
        }

        // 空白处起拖 = 重新框一个。
        selection = CGRect(origin: point, size: .zero)
        dragAnchor = point
        activeHandle = nil
        moveGrabOffset = nil
        emitUpdate()
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region else { return }
        let point = convert(event.locationInWindow, from: nil)
        didDrag = true

        if let offset = moveGrabOffset, var current = selection {
            current.origin = CGPoint(x: point.x - offset.width, y: point.y - offset.height)
            selection = clampToScreen(current)
            emitUpdate()
            return
        }

        if let handle = activeHandle, var current = selection, let _ = dragAnchor {
            current = resize(current, handle: handle, to: point)
            selection = clampToScreen(current)
            emitUpdate()
            return
        }

        if let anchor = dragAnchor {
            // 从起点拉出一个矩形。允许往任意方向拖。
            selection = clampToScreen(
                CGRect(
                    x: min(anchor.x, point.x),
                    y: min(anchor.y, point.y),
                    width: abs(point.x - anchor.x),
                    height: abs(point.y - anchor.y)
                )
            )
            emitUpdate()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region else { return }
        activeHandle = nil
        dragAnchor = nil
        moveGrabOffset = nil

        if let selection, selection.width < minimumSize || selection.height < minimumSize {
            // 只是点了一下，没拖动：清掉，重新来。
            self.selection = nil
        }
        emitUpdate()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let screen = window?.screen else { return }

        let candidates = windowCandidates?(screen) ?? []
        // 命中多个时取最小的那个——通常是用户真正想看的内容窗口，
        // 而不是它外面套着的整屏窗口。
        let hit = candidates
            .filter { $0.1.contains(point) }
            .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }

        if hit?.0.windowID != hoveredWindow?.windowID {
            hoveredWindow = hit?.0
            hoveredRect = hit?.1
            needsDisplay = true
            if let hit {
                onUpdate?(.window(hit.0))
            }
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / 小键盘回车
            guard selection != nil || hoveredWindow != nil else { return }
            onConfirm?()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 几何

    private func clampToScreen(_ rect: CGRect) -> CGRect {
        DisplayGeometry.clamp(rect, within: bounds, minimum: 1) ?? rect
    }

    private func resize(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft:     minX = point.x; maxY = point.y
        case .top:         maxY = point.y
        case .topRight:    maxX = point.x; maxY = point.y
        case .right:       maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom:      minY = point.y
        case .bottomLeft:  minX = point.x; minY = point.y
        case .left:        minX = point.x
        }

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> Handle? {
        for handle in Handle.allCases where handleRect(handle, in: rect).insetBy(
            dx: -handleHitSlop,
            dy: -handleHitSlop
        ).contains(point) {
            return handle
        }
        return nil
    }

    private func handleRect(_ handle: Handle, in rect: CGRect) -> CGRect {
        let half = handleSize / 2
        let x: CGFloat
        let y: CGFloat
        switch handle {
        case .topLeft:     x = rect.minX; y = rect.maxY
        case .top:         x = rect.midX; y = rect.maxY
        case .topRight:    x = rect.maxX; y = rect.maxY
        case .right:       x = rect.maxX; y = rect.midY
        case .bottomRight: x = rect.maxX; y = rect.minY
        case .bottom:      x = rect.midX; y = rect.minY
        case .bottomLeft:  x = rect.minX; y = rect.minY
        case .left:        x = rect.minX; y = rect.midY
        }
        return CGRect(x: x - half, y: y - half, width: handleSize, height: handleSize)
    }

    /// 把当前选区换算成 ScreenCaptureKit 的口径，交给外面。
    private func emitUpdate() {
        guard mode == .region else { return }
        defer { needsDisplay = true }

        guard let selection,
              selection.width >= minimumSize,
              selection.height >= minimumSize,
              let screen = window?.screen,
              let displayID = screen.displayID,
              let display = cachedDisplay(id: displayID)
        else {
            onUpdate?(nil)
            return
        }

        // 这里的翻转是整块功能最容易写错的地方：
        // 视图坐标原点在左下，sourceRect 的原点在左上。
        let sourceRect = DisplayGeometry.sourceRect(
            fromLocal: selection,
            screenHeight: screenHeight
        )
        let pixelSize = DisplayGeometry.pixelSize(forSourceRect: sourceRect, scale: imageScale)
        onUpdate?(.region(display: display, sourceRect: sourceRect, pixelSize: pixelSize))
    }

    /// 显示器和屏幕的对应关系，进入浮层时缓存一次就够。
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]

    func cacheDisplays(_ content: SCShareableContent?) {
        guard let content else { return }
        displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
    }

    private func cachedDisplay(id: CGDirectDisplayID) -> SCDisplay? {
        displays[id]
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 用奇偶填充规则一次性画出「整屏压暗、选区挖空」，
        // 比先铺满再用 clear 混合模式挖洞稳得多。
        let dim = NSBezierPath(rect: bounds)
        let highlight = selection ?? hoveredRect
        if let highlight {
            dim.appendRect(highlight)
        }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if let highlight {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: highlight)
            border.lineWidth = 1
            border.stroke()
        }

        if mode == .region, let selection {
            drawHandles(in: selection)
            drawSizeBadge(for: selection)
        }

        if selection == nil && hoveredRect == nil {
            drawHint()
        }
    }

    private func drawHandles(in rect: CGRect) {
        for handle in Handle.allCases {
            let box = handleRect(handle, in: rect)
            NSColor.white.setFill()
            NSBezierPath(rect: box).fill()
            NSColor.black.withAlphaComponent(0.4).setStroke()
            let outline = NSBezierPath(rect: box)
            outline.lineWidth = 0.5
            outline.stroke()
        }
    }

    private func drawSizeBadge(for rect: CGRect) {
        let pixelSize = DisplayGeometry.pixelSize(forSourceRect: rect, scale: imageScale)
        let text = "\(pixelSize.width) × \(pixelSize.height)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 4)

        // 选区贴着屏幕顶端时，标签放到里面，免得跑出屏幕看不见。
        let above = rect.maxY + size.height + padding.height * 2 + 6 <= bounds.maxY
        let origin = CGPoint(
            x: min(max(rect.minX, 0), max(0, bounds.maxX - size.width - padding.width * 2)),
            y: above ? rect.maxY + 6 : rect.maxY - size.height - padding.height * 2 - 6
        )

        let badge = CGRect(
            x: origin.x,
            y: origin.y,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(
            at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height),
            withAttributes: attributes
        )
    }

    private func drawHint() {
        let text = mode == .region
            ? "拖动鼠标框选区域　·　回车开始录制　·　Esc 取消"
            : "移动到要录制的窗口上，点一下选它　·　Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 16, height: 10)
        let badge = CGRect(
            x: bounds.midX - (size.width + padding.width * 2) / 2,
            y: bounds.midY - (size.height + padding.height * 2) / 2,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(
            at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height),
            withAttributes: attributes
        )
    }
}
