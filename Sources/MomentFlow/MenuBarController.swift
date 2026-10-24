import AppKit
import MomentFlowCore

/// 菜单栏：状态显示 + 入口。
///
/// 这里只负责「有哪些动作」，具体怎么录、录完怎么存都在 `CaptureCoordinator`。
@MainActor
final class MenuBarController: NSObject {

    /// 每次都现读：用户可能在中途换了素材库位置。
    private var store: MomentStore {
        MomentStore(root: settings.libraryRoot)
    }
    private let capturer = MomentCapturer()
    private let notePanel = NotePanel()
    private let capture = CaptureCoordinator()
    private let welcome = WelcomeWindowController()
    private let settingsWindow = SettingsWindowController()
    private let settings = AppSettings.shared

    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var timer: Timer?

    private var lastMomentFile: URL?
    private var editingMoment: MediaMoment?
    private var editingFile: URL?

    /// 上一次真正画到菜单栏上的内容。用来跳过没必要的重绘。
    private var lastRenderedRecording = false
    private var lastRenderedTitle = ""
    private var lastRenderedStatusLine = ""

    private static let welcomeKey = "hasSeenWelcome"

    // MARK: - 安装

    func install() {
        settings.onHotkeysChanged = { [weak self] in
            self?.applyHotkeys(reportFailures: false)
            self?.rebuildMenu()
        }
        settings.onLibraryRootChanged = { [weak self] in
            self?.rebuildMenu()
            self?.refreshStatus()
        }
        settingsWindow.onGrantScreenRecording = { [weak self] in
            self?.grantScreenRecording()
        }

        welcome.onGrantScreenRecording = { [weak self] in
            self?.grantScreenRecording()
        }
        welcome.onOpenLibrary = { [weak self] in
            self?.openLibrary()
        }

        capture.onStateChange = { [weak self] in
            self?.rebuildMenu()
            self?.refreshStatus()
        }
        capture.onSaved = { [weak self] fileURL in
            self?.lastMomentFile = fileURL
            self?.rebuildMenu()
        }
        capture.onAlert = { [weak self] alert in
            self?.show(alert)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.idleImage
        statusItem = item

        rebuildMenu()
        applyHotkeys(reportFailures: true)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshStatus()

        // 纯菜单栏应用不会弹出窗口。第一次启动如果不主动露个面，
        // 用户看到的就只是「双击了但什么都没发生」。
        if !UserDefaults.standard.bool(forKey: Self.welcomeKey) {
            UserDefaults.standard.set(true, forKey: Self.welcomeKey)
            welcome.show()
        }
    }

    /// App 已经开着的时候又去双击图标，就把说明窗口调出来。
    func showWelcome() {
        welcome.refresh()
        welcome.show()
    }

    var isRecording: Bool { capture.isRecording }

    /// 退出前把正在录的那一段收尾。返回之后文件已经写完。
    func finalizeBeforeQuit() async {
        await capture.stopAndFinalize()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        if capture.isRecording {
            capture.stop()
        }
        welcome.close()
        settingsWindow.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    /// 按当前设置整组重注册。
    ///
    /// - Parameter reportFailures: 启动时给一次弹窗提示；用户在设置界面里
    ///   反复调的时候只做行内标注，不然会一直弹。
    private func applyHotkeys(reportFailures: Bool) {
        HotkeyCenter.shared.unregisterAll()
        var issues: [AppSettings.HotkeySlot: String] = [:]

        func bind(
            _ slot: AppSettings.HotkeySlot,
            action: @escaping (MenuBarController) -> Void
        ) {
            let combo = settings.combo(for: slot)
            let registered = HotkeyCenter.shared.register(combo) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    action(self)
                }
            }
            if registered == nil {
                issues[slot] = "\(combo.display) 被别的软件占用了，这个功能只能用菜单点。"
            }
        }

        bind(.quickRecord) { $0.capture.toggleQuickRecord() }
        bind(.capture) { $0.capture.present() }
        bind(.marker) { $0.captureMoment() }

        settings.hotkeyIssues = issues

        if reportFailures, !issues.isEmpty {
            // 注册失败时快捷键是彻底无声失效的，必须说一声。
            let names = issues.keys.map(\.title).joined(separator: "、")
            report("有快捷键没注册上", "\(names) 的组合被别的软件占着了，对应的功能只能用菜单点。")
        }
    }

    // MARK: - 菜单

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())
        menu.addItem(item(
            "采集片段…",
            #selector(menuPresentCapture),
            hint: settings.combo(for: .capture).display
        ))
        menu.addItem(item(
            capture.isRecording ? "停止录制" : "快速录制当前窗口",
            #selector(menuQuickRecord),
            hint: settings.combo(for: .quickRecord).display
        ))
        menu.addItem(item(
            "记一个点",
            #selector(menuCapture),
            hint: settings.combo(for: .marker).display
        ))

        menu.addItem(.separator())
        menu.addItem(item("打开素材库", #selector(menuOpenLibrary)))
        menu.addItem(item(
            "打开最近一个记录",
            #selector(menuOpenLastMoment),
            enabled: lastMomentFile != nil
        ))
        menu.addItem(item("设置…", #selector(menuShowSettings)))

        menu.addItem(.separator())
        menu.addItem(item("快捷键说明…", #selector(menuShowWelcome)))
        menu.addItem(.separator())
        addPermissionItems(to: menu)

        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(menuQuit)))

        statusItem?.menu = menu
    }

    /// 快捷键提示直接写在标题里。
    ///
    /// 不设 `keyEquivalent` 是因为快捷键由 Carbon 全局注册，
    /// 再让菜单也认同一个组合，App 在前台时会触发两次。
    private func item(_ title: String, _ action: Selector, hint: String? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: hint.map { "\(title)　\($0)" } ?? title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func addPermissionItems(to menu: NSMenu) {
        if CapturePermission.hasScreenRecording {
            let granted = NSMenuItem(title: "屏幕录制权限：已授权", action: nil, keyEquivalent: "")
            granted.isEnabled = false
            menu.addItem(granted)
        } else {
            menu.addItem(item("授予屏幕录制权限…", #selector(menuRequestScreenRecording)))
        }

        // 这里以前还会显示麦克风权限状态，但每次查状态都会在系统日志里
        // 留下一条 kTCCServiceMicrophone 记录。既然本工具根本不用麦克风，
        // 就没必要去碰它——少一个权限、少一次系统检查。
    }

    private func statusLine() -> String {
        if capture.isRecording {
            return "录制中 \(capture.elapsedText)"
        }
        return "素材库：\(displayPath(store.root))"
    }

    private func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    // MARK: - 记一个点

    func captureMoment() {
        guard requireScreenRecording() else { return }

        Task { @MainActor in
            let window = FrontmostWindow.current()
            let now = Date()
            var moment = MediaMoment(
                id: MediaMoment.makeID(date: now, windowTitle: window.windowTitle, appName: window.appName),
                kind: .marker,
                createdAt: now,
                appName: window.appName,
                bundleIdentifier: window.bundleIdentifier,
                windowTitle: window.windowTitle
            )

            do {
                let data = try await capturer.captureScreenshot()
                // 文件名可能因为撞名被加了后缀，id 要跟着走。
                let fileName = store.uniqueFileName(base: moment.id, extension: "png")
                moment.id = (fileName as NSString).deletingPathExtension
                try store.writeScreenshot(data, as: fileName)
                moment.files.screenshot = fileName

                try store.save(moment)
                let fileURL = store.fileURL(fileName)
                lastMomentFile = fileURL
                rebuildMenu()
                openNotePanel(for: moment, fileURL: fileURL)
            } catch {
                report("记点失败", error.localizedDescription)
            }
        }
    }

    // MARK: - 便签

    private func openNotePanel(for moment: MediaMoment, fileURL: URL) {
        editingMoment = moment
        editingFile = fileURL

        notePanel.show(
            header: moment.displayTitle,
            subheader: "\(moment.appName ?? "未知来源")　·　\(fileURL.lastPathComponent)",
            initialText: moment.note
        ) { [weak self] text in
            self?.saveNote(text)
        }
    }

    private func saveNote(_ text: String) {
        guard var moment = editingMoment, editingFile != nil else { return }
        moment.note = text
        do {
            try store.save(moment)
            editingMoment = moment
        } catch {
            report("笔记没存上", error.localizedDescription)
        }
    }

    // MARK: - 状态

    private func refreshStatus() {
        guard let button = statusItem?.button else { return }

        let recording = capture.isRecording
        let title = recording ? " \(capture.elapsedText)" : ""

        // 只在真的变了的时候动按钮。
        //
        // 这个 Timer 每 0.5 秒跑一次。若无条件重设图标和标题，
        // 每次都要从 bundle 读取并解码图标，空闲时也会持续占用 CPU。
        if recording != lastRenderedRecording {
            button.image = recording ? Self.recordingImage : Self.idleImage
            button.contentTintColor = recording ? .systemRed : nil
            lastRenderedRecording = recording
        }
        if title != lastRenderedTitle {
            button.title = title
            lastRenderedTitle = title
        }

        let status = statusLine()
        if status != lastRenderedStatusLine {
            statusMenuItem?.title = status
            lastRenderedStatusLine = status
        }
    }

    /// 菜单栏用自己画的模板图标：黑色 + alpha，系统按深浅色自动反色。
    ///
    /// 用 `let` 只读一次；写成计算属性的话每次访问都要读文件加解码。
    private static let idleImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "record.circle", accessibilityDescription: "MomentFlow")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private static let recordingImage: NSImage? = {
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "录制中")
        image?.isTemplate = true
        return image
    }()

    // MARK: - 菜单动作

    @objc private func menuPresentCapture() { capture.present() }
    @objc private func menuQuickRecord() { capture.toggleQuickRecord() }
    @objc private func menuCapture() { captureMoment() }

    @objc private func menuOpenLibrary() {
        openLibrary()
    }

    private func openLibrary() {
        try? FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.root)
    }

    @objc private func menuShowWelcome() { showWelcome() }

    @objc private func menuShowSettings() {
        settingsWindow.show(settings: settings)
    }

    @objc private func menuOpenLastMoment() {
        guard let lastMomentFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastMomentFile])
    }

    @objc private func menuRequestScreenRecording() {
        grantScreenRecording()
    }

    /// 申请屏幕录制权限，并把用户直接送到该去的地方。
    ///
    /// 只弹一句「去系统设置里打开」是不够的：被拒之后系统不会再自动弹框，
    /// 而那个面板藏在「隐私与安全性」下面好几层。
    /// 更常见的是这个 App 根本还没出现在列表里，得手动点「+」加进来——
    /// 光让用户「去系统设置里打开」，他会卡在"打开哪个、找不到"这一步。
    private func grantScreenRecording() {
        // 会弹系统授权框；已经被拒过的话它直接返回 false，不再弹。
        _ = CapturePermission.requestScreenRecording()

        show(UserAlert(
            "在系统设置里给 MomentFlow 授权",
            """
            1. 列表里找到 MomentFlow，把右边的开关打开

            2. 列表里没有它：点列表下方的「+」，选这个文件
               \(Bundle.main.bundlePath)

            3. 如果有一条 MomentFlow 但开关打不开：先用「−」把它删掉，再从第 2 步重新加

            授权之后必须退出本应用、再重新打开才生效。
            """,
            actionTitle: "打开系统设置",
            action: { CapturePermission.openScreenRecordingSettings() }
        ))
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - 提示

    private func requireScreenRecording() -> Bool {
        guard CapturePermission.hasScreenRecording else {
            // 直接给入口，别只说一句"去系统设置"就把人打发了。
            grantScreenRecording()
            return false
        }
        return true
    }

    private func report(_ title: String, _ message: String) {
        show(UserAlert(title, message))
    }

    /// 弹窗只用来打断真正需要用户处理的事。
    /// 带动作按钮的时候，第一个按钮是动作，第二个是"知道了"。
    private func show(_ userAlert: UserAlert) {
        let panel = NSAlert()
        panel.messageText = userAlert.title
        panel.informativeText = userAlert.message
        panel.alertStyle = .warning

        let hasAction = userAlert.actionTitle != nil && userAlert.action != nil
        panel.addButton(withTitle: hasAction ? userAlert.actionTitle! : "好")
        if hasAction {
            panel.addButton(withTitle: "知道了")
        }

        NSApp.activate(ignoringOtherApps: true)
        // 只有点了那个动作按钮才跳转，"知道了"不该顺手把系统设置拉起来。
        if panel.runModal() == .alertFirstButtonReturn, hasAction {
            userAlert.action?()
        }
    }
}
