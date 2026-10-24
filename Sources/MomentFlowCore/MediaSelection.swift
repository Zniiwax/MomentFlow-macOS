import Foundation

/// 这一次录什么。
///
/// 只有两个维度：画面、系统声音。麦克风刻意不做——录制片段是为了拿素材，
/// 不是录解说；真需要人声的时候单独开个录音工具更省事，也省掉一个权限。
public struct MediaSelection: Codable, Hashable, Sendable {
    public var video: Bool
    /// 系统声音：电影里的台词、音乐、游戏音效。
    public var systemAudio: Bool

    public init(video: Bool = true, systemAudio: Bool = true) {
        self.video = video
        self.systemAudio = systemAudio
    }

    public static let videoWithAudio = MediaSelection(video: true, systemAudio: true)
    public static let videoOnly = MediaSelection(video: true, systemAudio: false)
    public static let audioOnly = MediaSelection(video: false, systemAudio: true)

    /// 两个都不选就没得录了。
    public var isValid: Bool { video || systemAudio }

    /// 只有声音时存 m4a，否则存 mp4。
    public var fileExtension: String { video ? "mp4" : "m4a" }

    public var summary: String {
        switch (video, systemAudio) {
        case (true, true): return "画面 + 系统声音"
        case (true, false): return "只有画面"
        case (false, true): return "只有系统声音"
        case (false, false): return "还没选内容"
        }
    }
}
