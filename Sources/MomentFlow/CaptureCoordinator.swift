import AppKit
import MomentFlowCore
import ScreenCaptureKit

/// 要弹给用户看的东西。
///
/// 带一个可选的动作按钮：权限类的提示光说"没权限"没用，
/// 得让用户能一步跳到该去的地方。
struct UserAlert {
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, _ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
}

/// 片段采集的调度中心：工具栏 → 选范围 → 录制 → 落盘。
@MainActor
final class CaptureCoordinator: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case screen
        case window
        case region

        var id: String { rawValue }

        var title: String {
            switch self {
            case .screen: return "整屏"
            case .window: return "窗口"
            case .region: return "选区"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case selecting
        case starting
        case recording
    }

    @Published var mode: Mode {
        didSet {
            // 初始化时也会走到这里，用 stage 挡一下，避免构造过程中就去拉屏幕信息。
            guard mode != oldValue, stage != .idle else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            beginSelection()
        }
    }

    @Published var media: MediaSelection {
        didSet {
            guard media != oldValue else { return }
            if stage == .recording {
                // 录制中改媒体选择没有意义，立刻改回来。
                media = activeMedia
                return
            }
            settings.setDefaultMedia(media)
        }
    }

    @Published private(set) var stage: Phase = .idle
    @Published private(set) var target: SelectionTarget?
    @Published private(set) var elapsed: TimeInterval = 0

    var onSaved: ((URL) -> Void)?
    var onStateChange: (() -> Void)?
    var onAlert: ((UserAlert) -> Void)?

    private static let modeKey = "capture.mode"

    private let defaults = UserDefaults.standard
    private let settings = AppSettings.shared
    private let selection = SelectionOverlayController()
    private let toolbar = CaptureToolbarPanel()
    private let recorder = ClipRecorder()
    private let toast = SavedToast()
    /// 每次都现读：用户可能在中途换了素材库位置。
    private var store: MomentStore {
        MomentStore(root: settings.libraryRoot)
    }

    private var timer: Timer?
    private var startedAt: Date?
    private var staging: URL?
    /// 录制成功但落盘失败时，把临时文件留下，别把用户刚录的东西删了。
    private var keepStagingOnFinish = false
    private var activeMedia = MediaSelection.videoWithAudio

    init() {
        let saved = defaults.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:))
        mode = saved ?? .region
        media = settings.defaultMedia
        wireSelection()
    }

    var isRecording: Bool {
        stage == .recording
    }

    var canStart: Bool {
        media.isValid && target != nil && stage == .selecting
    }

    var elapsedText: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 工具栏

    /// `⌥⌘5`：打开采集工具栏。
    func present() {
        guard stage == .idle else { return }
        guard requireScreenRecording() else { return }
        stage = .selecting
        target = nil
        toolbar.show(coordinator: self)
        beginSelection()
        onStateChange?()
    }

    /// 取消这次采集（还没开始录的时候）。
    func dismiss() {
        guard stage == .selecting || stage == .starting else { return }
        selection.dismiss()
        toolbar.hide()
        finishSession()
    }

    private func wireSelection() {
        selection.onUpdate = { [weak self] target in
            guard let self else { return }
            self.target = target
            self.toolbar.resizeToFit()
        }
        selection.onConfirm = { [weak self] in
            guard let self, self.canStart else { return }
            self.start()
        }
        selection.onCancel = { [weak self] in
            self?.dismiss()
        }
    }

    // MARK: - 选范围

    private func beginSelection() {
        guard stage == .selecting else { return }

        Task { @MainActor in
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
            } catch {
                report(
                    "读不到屏幕信息",
                    "多半是屏幕录制权限没给。菜单里点「授予屏幕录制权限…」，授权后退出重开本应用。"
                )
                return
            }
            // 拉一次屏幕信息要几百毫秒，期间用户可能又换了模式，所以再确认一次。
            guard stage == .selecting else { return }

            switch mode {
            case .screen:
                selection.dismiss()
                guard let display = Self.displayUnderCursor(in: content) else {
                    target = nil
                    return
                }
                target = .display(display)
            case .window:
                target = nil
                selection.begin(mode: .window, content: content)
            case .region:
                target = nil
                selection.begin(mode: .region, content: content)
            }
            toolbar.resizeToFit()
        }
    }

    static func displayUnderCursor(in content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let id = screen?.displayID,
           let display = content.displays.first(where: { $0.displayID == id }) {
            return display
        }
        return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    }

    // MARK: - 录制

    func start() {
        guard canStart, let target else { return }
        guard requireScreenRecording() else {
            stage = .selecting
            return
        }
        stage = .starting

        Task { @MainActor in
            do {
                let source = try Self.source(for: target)
                let staging = try Self.makeStagingDirectory()
                let selected = media
                let url = staging.appendingPathComponent("clip.\(selected.fileExtension)")

                try await recorder.start(source: source, media: selected, outputURL: url)

                self.staging = staging
                activeMedia = selected
                selection.dismiss()
                startedAt = Date()
                elapsed = 0
                stage = .recording
                startTimer()
                toolbar.resizeToFit()
                onStateChange?()
            } catch {
                stage = .selecting
                report("开始录制失败", error.localizedDescription)
            }
        }
    }

    /// `⌘⇧R`：不打开工具栏，直接录当前前台窗口。再按一次停。
    func toggleQuickRecord() {
        if stage == .recording {
            stop()
            return
        }
        guard stage == .idle else { return }
        // 先查权限。不做这一步的话，用户要框完选区、点了开始，才被告知没权限。
        guard requireScreenRecording() else { return }
        stage = .starting

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                let processID = FrontmostWindow.current().processID
                guard let window = MomentCapturer.frontmostWindow(in: content, processID: processID) else {
                    throw ClipRecorder.Failure.noCaptureTarget
                }

                let staging = try Self.makeStagingDirectory()
                let selected = media
                let url = staging.appendingPathComponent("clip.\(selected.fileExtension)")
                try await recorder.start(source: .window(window), media: selected, outputURL: url)

                self.staging = staging
                activeMedia = selected
                startedAt = Date()
                elapsed = 0
                stage = .recording
                startTimer()
                onStateChange?()
            } catch {
                stage = .idle
                report("开始录制失败", error.localizedDescription)
            }
        }
    }

    func stop() {
        guard stage == .recording else { return }
        Task { await finalizeRecording() }
    }

    /// 停止并等文件真正写完。
    ///
    /// 退出 App 的时候必须走这条：直接退进程的话，AVAssetWriter 还没收尾，
    /// 录了半天的文件就是坏的。
    func stopAndFinalize() async {
        guard stage == .recording else { return }
        await finalizeRecording()
    }

    private func finalizeRecording() async {
        guard stage == .recording else { return }
        stopTimer()
        stage = .starting

        do {
            let result = try await recorder.stop()
            do {
                try await save(result)
            } catch {
                // 录是录成了，只是没进素材库（比如桌面文件夹权限被拒）。
                // 这时候把文件删掉等于白录，留原地并说清楚在哪。
                keepStagingOnFinish = true
                report(
                    "录好了，但没存进素材库",
                    "\(error.localizedDescription)\n\n文件先留在这儿：\n\(result.url.deletingLastPathComponent().path)"
                )
            }
        } catch {
            // 录制中途出错。文件很可能还是好的（只是少了尾巴），
            // 所以只要它有点内容就别删——删掉等于把用户刚录的东西扔掉。
            if let kept = keepStagingIfUsable() {
                report(
                    "录制中断了",
                    "\(error.localizedDescription)\n\n已录到的部分留在这儿：\n\(kept.path)"
                )
            } else {
                report("录制失败", error.localizedDescription)
            }
        }
        finishSession()
    }

    /// 临时目录里的文件如果像样，就留下来并返回它的路径。
    private func keepStagingIfUsable() -> URL? {
        guard let staging else { return nil }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let usable = contents.first { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // 十几 K 以下基本就是个空壳（只有文件头），留着没意义。
            return size > 32 * 1024
        }
        guard usable != nil else { return nil }
        keepStagingOnFinish = true
        return staging
    }

    /// 丢弃这一段，不留文件。
    func discard() {
        guard stage == .recording else { return }
        stopTimer()
        stage = .starting

        Task { @MainActor in
            _ = try? await recorder.stop()
            finishSession()
        }
    }

    private func save(_ result: ClipRecorder.Result) async throws {
        let window = FrontmostWindow.current()
        let now = Date()

        var moment = MediaMoment(
            id: MediaMoment.makeID(date: now, windowTitle: window.windowTitle, appName: window.appName),
            kind: .clip,
            createdAt: now,
            appName: window.appName,
            bundleIdentifier: window.bundleIdentifier,
            windowTitle: window.windowTitle,
            duration: result.duration,
            media: activeMedia
        )

        // 文件名可能因为撞名被加了后缀，id 要跟着走——
        // 索引里的 id 和磁盘上的文件名必须是同一个，否则以后按 id 找不到文件。
        let fileName = store.uniqueFileName(base: moment.id, extension: activeMedia.fileExtension)
        moment.id = (fileName as NSString).deletingPathExtension

        try store.place(result.url, as: fileName)
        moment.files.clip = fileName

        try store.save(moment)
        let fileURL = store.fileURL(fileName)
        onSaved?(fileURL)

        toast.show(SavedToast.Content(
            title: "已保存",
            detail: Self.describeClip(duration: result.duration, media: activeMedia),
            path: Self.abbreviate(fileURL.path),
            fileURL: fileURL
        ))
    }

    /// 「14 秒 · 画面 + 系统声音」这种一行摘要。
    static func describeClip(duration: TimeInterval, media: MediaSelection) -> String {
        let seconds = Int(duration.rounded())
        let length = seconds >= 60
            ? String(format: "%d 分 %02d 秒", seconds / 60, seconds % 60)
            : "\(seconds) 秒"
        return "\(length) · \(media.summary)"
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func finishSession() {
        stopTimer()
        toolbar.hide()
        selection.dismiss()
        if let staging, !keepStagingOnFinish {
            try? FileManager.default.removeItem(at: staging)
        }
        keepStagingOnFinish = false
        staging = nil
        startedAt = nil
        elapsed = 0
        target = nil
        stage = .idle
        onStateChange?()
    }

    // MARK: - 计时

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = self.recorder.recordedDuration
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 工具

    static func source(for target: SelectionTarget) throws -> ClipRecorder.Source {
        switch target {
        case .display(let display):
            return .display(display)
        case .region(let display, let sourceRect, _):
            return .region(display: display, rect: sourceRect)
        case .window(let window):
            return .window(window)
        }
    }

    static func makeStagingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func report(_ title: String, _ message: String) {
        onAlert?(UserAlert(title, message))
    }

    /// 屏幕录制权限不够时给一句能照做的话，并且给个直接跳过去的入口。
    private func requireScreenRecording() -> Bool {
        guard !CapturePermission.hasScreenRecording else { return true }

        // 先真的调一次系统申请接口。
        //
        // 这一步以前漏了，后果很隐蔽：系统的授权框只在 App **真的尝试录屏**时才出现。
        // 如果权限不够就直接拦住、只弹自己的提示，那 App 永远不会尝试，
        // 系统就永远不会把本 App 加进「屏幕录制」列表——用户打开系统设置，
        // 列表里根本没有 MomentFlow，想授权都没地方点。
        if CapturePermission.requestScreenRecording() {
            return true
        }

        onAlert?(UserAlert(
            "还缺屏幕录制权限",
            "截图和录制都要它。授权之后必须退出再重新打开本应用才生效。",
            actionTitle: "打开系统设置",
            action: { CapturePermission.openScreenRecordingSettings() }
        ))
        return false
    }
}
