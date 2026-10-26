import Foundation

/// 这一次录什么。
///
/// 只有两个维度：画面、系统声音。麦克风刻意不做——录制片段是为了拿素材，
/// 不是录解说；真需要人声的时候单独开个录音工具更省事，也省掉一个权限。
public struct MediaSelection: Codable, Hashable, Sendable {
    public var video: Bool
    /// 系统声音：电影里的台词、音乐、游戏音效。
    public var systemAudio: Bool
    /// 麦克风：单独存一轨，方便之后转写或单独调音量。
    public var microphone: Bool

    public init(video: Bool = true, systemAudio: Bool = true, microphone: Bool = false) {
        self.video = video
        self.systemAudio = systemAudio
        self.microphone = microphone
    }

    public static let videoWithAudio = MediaSelection(video: true, systemAudio: true, microphone: false)
    public static let videoOnly = MediaSelection(video: true, systemAudio: false, microphone: false)
    public static let audioOnly = MediaSelection(video: false, systemAudio: true, microphone: false)

    /// 旧版本的数据里没有 microphone 字段，解码时补成 false。
    enum CodingKeys: String, CodingKey {
        case video
        case systemAudio
        case microphone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decodeIfPresent(Bool.self, forKey: .video) ?? true
        systemAudio = try container.decodeIfPresent(Bool.self, forKey: .systemAudio) ?? true
        microphone = try container.decodeIfPresent(Bool.self, forKey: .microphone) ?? false
    }

    /// 画面和系统声音都不选就没得录了。
    /// 麦克风是叠加项，不能单独撑起一次录制。
    public var isValid: Bool { video || systemAudio }

    /// 只有声音时存 m4a，否则存 mp4。
    public var fileExtension: String { video ? "mp4" : "m4a" }

    public var summary: String {
        var parts: [String] = []
        if video { parts.append("画面") }
        if systemAudio { parts.append("系统声音") }
        if microphone { parts.append("麦克风") }
        return parts.isEmpty ? "还没选内容" : parts.joined(separator: " + ")
    }
}
