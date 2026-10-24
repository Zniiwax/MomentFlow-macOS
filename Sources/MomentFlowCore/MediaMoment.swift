import Foundation

/// 一次记录的元数据，落盘为 `moment.json`。
///
/// 这个结构是整个项目的重心：素材画面其实是次要的，真正值钱的是
/// 「什么时间、我在看什么、我当时想到了什么」。所以元数据字段是必填项，
/// 而截图 / 录像是可选附件。
public struct MediaMoment: Codable, Hashable, Sendable, Identifiable {

    /// 记录的形态。
    public enum Kind: String, Codable, Sendable {
        /// 只记点：一张截图 + 元数据 + 笔记。
        case marker
        /// 录了一小段：画面 + 系统声音（麦克风单独一轨）。
        case clip
    }

    /// 片段目录里的附件。值一律存相对文件名，这样整个素材库可以整体搬家。
    public struct Files: Codable, Hashable, Sendable {
        public var screenshot: String?
        public var clip: String?
        /// 你的声音，和系统声音分开存。
        public var microphone: String?
        public var note: String?
        /// 预留：语音转写结果，直接可以当配音初稿改。
        public var transcript: String?

        public init(
            screenshot: String? = nil,
            clip: String? = nil,
            microphone: String? = nil,
            note: String? = nil,
            transcript: String? = nil
        ) {
            self.screenshot = screenshot
            self.clip = clip
            self.microphone = microphone
            self.note = note
            self.transcript = transcript
        }
    }

    /// 同时是片段目录名，例如 `2026-10-08_2130_怪奇物语-S4E7`。
    public var id: String
    public var kind: Kind
    public var createdAt: Date
    /// 前台 App，例如 Safari / IINA / Music。
    public var appName: String?
    public var bundleIdentifier: String?
    /// 前台窗口标题。播放器通常把剧名 / 曲名写在这里，是最省事的来源。
    public var windowTitle: String?
    /// 你当时的想法。
    public var note: String
    /// 片段时长（秒）。marker 为 nil。
    public var duration: TimeInterval?
    /// 录了什么（画面 / 系统声音）。只对 clip 有意义，老数据里没有这个字段。
    public var media: MediaSelection?
    public var files: Files

    public init(
        id: String,
        kind: Kind,
        createdAt: Date,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        note: String = "",
        duration: TimeInterval? = nil,
        media: MediaSelection? = nil,
        files: Files = Files()
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.note = note
        self.duration = duration
        self.media = media
        self.files = files
    }

    /// 列表里显示什么。
    public var displayTitle: String {
        if let windowTitle, !windowTitle.isEmpty { return windowTitle }
        if let appName, !appName.isEmpty { return appName }
        return "未命名"
    }

    /// 生成目录名：时间戳 + 标题摘要。
    public static func makeID(date: Date, windowTitle: String?, appName: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // 精确到秒：同一部剧同一分钟里连按两次是常事，只到分钟会互相覆盖。
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let stamp = formatter.string(from: date)
        let slug = slugify(windowTitle ?? appName ?? "")
        return slug.isEmpty ? stamp : "\(stamp)_\(slug)"
    }

    /// 洗成能直接当文件夹名的字符串。
    ///
    /// 窗口标题里带 `/`、`:` 是家常便饭（「第 1 集 / 第一季」），
    /// 直接拿来建目录会失败或者建出奇怪的层级，所以先替换掉再截断。
    static func slugify(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = raw.components(separatedBy: illegal).joined(separator: " ")
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        return String(collapsed.prefix(40))
    }
}
