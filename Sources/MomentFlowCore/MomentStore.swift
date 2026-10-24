import Foundation

/// 素材库的落盘布局。
///
///     ~/Desktop/MomentFlow/
///       index.jsonl                                  所有元数据，一行一条
///       2026-10-11_142805_怪奇物语-S4E7.mp4          录制的画面 + 系统声音
///       2026-10-11_143010_怪奇物语-S4E7.m4a          只录了声音时
///       2026-10-11_143500_怪奇物语-S4E7.png          ⌥⌘M 记的点，一张截图
///
/// **平铺，一个录制就是一个文件。**
///
/// 不套文件夹，是因为录完通常要直接拖进剪辑软件：
/// 多一层目录就得多点开一次，才知道里面是什么。
///
/// 元数据不再单独落一个 moment.json —— `index.jsonl` 里本来就是完整的一份，
/// 分成两个文件既冗余、又有对不上的风险（真的对不上过，见下面 createFolder 的注释）。
/// 笔记同理，只存在索引里。
public struct MomentStore {

    public enum StoreError: LocalizedError {
        case cannotPlaceFile(path: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .cannotPlaceFile(let path, let reason):
                return "文件放不进素材库（\(path)）：\(reason)"
            }
        }
    }

    public static let indexName = "index.jsonl"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 默认素材库位置：桌面上的 MomentFlow 文件夹。
    ///
    /// 放桌面是因为这是个天天用的工作区——录完马上要拖进剪映，
    /// 埋在 ~/Movies 里要多走好几步。
    public static func defaultRoot() -> URL {
        let desktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        return desktop.appendingPathComponent("MomentFlow", isDirectory: true)
    }

    /// 实际用的位置：用户在设置里选过就用选的，没选过就用默认的。
    public static func configuredRoot(defaults: UserDefaults = .standard) -> URL {
        guard let path = defaults.string(forKey: rootPreferenceKey), !path.isEmpty else {
            return defaultRoot()
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func setConfiguredRoot(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.path, forKey: rootPreferenceKey)
    }

    public static func resetConfiguredRoot(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: rootPreferenceKey)
    }

    public static let rootPreferenceKey = "library.root"

    public var indexURL: URL {
        root.appendingPathComponent(Self.indexName)
    }

    /// 素材库里某个文件的完整路径。
    public func fileURL(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// 找一个还没被占用的文件名。
    ///
    /// 文件名来自「时间戳 + 窗口标题」，只精确到秒。同一秒里连按两次记点，
    /// 或者快速录制连开两次，就会撞名——撞名必须往后排，
    /// 直接用的话第二次会把第一次的文件覆盖掉，而且是无声的。
    public func uniqueFileName(base: String, extension ext: String) -> String {
        var candidate = "\(base).\(ext)"
        var suffix = 2
        while FileManager.default.fileExists(atPath: fileURL(candidate).path) {
            candidate = "\(base)-\(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }

    /// 把录好的文件从临时目录搬进素材库。
    @discardableResult
    public func place(_ source: URL, as fileName: String) throws -> URL {
        let destination = fileURL(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw StoreError.cannotPlaceFile(path: destination.path, reason: error.localizedDescription)
        }
        return destination
    }

    /// 写一张截图（⌥⌘M 记点用）。
    @discardableResult
    public func writeScreenshot(_ data: Data, as fileName: String) throws -> URL {
        let destination = fileURL(fileName)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw StoreError.cannotPlaceFile(path: destination.path, reason: error.localizedDescription)
        }
        return destination
    }

    // MARK: - 索引

    /// 记录一条素材。元数据只进索引，不再单独落文件。
    public func save(_ moment: MediaMoment) throws {
        try upsertIndex(moment)
    }

    /// 追加或就地替换索引里的一行。
    ///
    /// 用 jsonl 而不是数据库：一行一条、可以直接 cat / grep，
    /// 后面接 AI 批处理时不用装任何依赖。
    public func upsertIndex(_ moment: MediaMoment) throws {
        var moments = try loadIndex()
        if let index = moments.firstIndex(where: { $0.id == moment.id }) {
            moments[index] = moment
        } else {
            moments.append(moment)
        }
        try rewriteIndex(moments)
    }

    public func loadIndex() throws -> [MediaMoment] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let content = try String(contentsOf: indexURL, encoding: .utf8)
        return content
            .split(separator: "\n")
            .compactMap { line -> MediaMoment? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? Self.indexDecoder.decode(MediaMoment.self, from: data)
            }
    }

    private func rewriteIndex(_ moments: [MediaMoment]) throws {
        let lines = try moments.map { String(decoding: try Self.indexEncoder.encode($0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            .write(to: indexURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 编码器

    /// 索引是逐行 JSON，不能带换行。
    static var indexEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var indexDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
