import XCTest
@testable import MomentFlowCore

/// 素材库是**平铺**的：一个录制就是一个文件，不套文件夹。
final class MomentStoreTests: XCTestCase {

    private func makeStore() -> (MomentStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MomentFlowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (MomentStore(root: root), root)
    }

    private func makeMoment(
        windowTitle: String? = "怪奇物语 S4E7",
        appName: String? = "IINA",
        kind: MediaMoment.Kind = .clip
    ) -> MediaMoment {
        let now = Date()
        return MediaMoment(
            id: MediaMoment.makeID(date: now, windowTitle: windowTitle, appName: appName),
            kind: kind,
            createdAt: now,
            appName: appName,
            bundleIdentifier: "com.colliderli.iina",
            windowTitle: windowTitle
        )
    }

    // MARK: - 平铺布局

    func testSaveOnlyWritesIndexAndNoFolder() throws {
        // 这是一条回归测试。
        //
        // 之前是「一个录制一个文件夹」，保存流程里建目录被调用了两次：
        // 旧实现两次返回同一个目录所以看不出来，后来加了「撞名自动加后缀」，
        // 第二次就变成了 `xxx-2`，于是每录一次都多出一个只装元数据的空文件夹。
        // 改成平铺之后，磁盘上除了索引不该再有任何东西。
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var moment = makeMoment()
        moment.files.clip = "\(moment.id).mp4"
        try store.save(moment)

        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(entries, [MomentStore.indexName], "除了索引不该有别的文件")

        let indexed = try store.loadIndex()
        XCTAssertEqual(indexed.count, 1)
        XCTAssertEqual(indexed.first?.id, moment.id)
    }

    func testFilesLandDirectlyInRoot() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("fake video".utf8).write(to: staging)

        let placed = try store.place(staging, as: "录制.mp4")

        XCTAssertEqual(placed.deletingLastPathComponent().standardizedFileURL,
                       root.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: placed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path), "源文件应该被搬走")
    }

    func testScreenshotLandsInRoot() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let written = try store.writeScreenshot(Data("png".utf8), as: "记点.png")
        XCTAssertEqual(written.deletingLastPathComponent().standardizedFileURL,
                       root.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: written), Data("png".utf8))
    }

    // MARK: - 撞名

    func testUniqueFileNameAvoidsCollision() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(store.uniqueFileName(base: "abc", extension: "mp4"), "abc.mp4")

        try Data("x".utf8).write(to: store.fileURL("abc.mp4"))
        XCTAssertEqual(store.uniqueFileName(base: "abc", extension: "mp4"), "abc-2.mp4")

        try Data("x".utf8).write(to: store.fileURL("abc-2.mp4"))
        XCTAssertEqual(store.uniqueFileName(base: "abc", extension: "mp4"), "abc-3.mp4")
    }

    func testDifferentExtensionsDoNotCollide() throws {
        // 同一秒里先录一段视频、再记一个点，两者的 base 名相同但扩展名不同，
        // 不该互相挤占。
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("x".utf8).write(to: store.fileURL("abc.mp4"))
        XCTAssertEqual(store.uniqueFileName(base: "abc", extension: "png"), "abc.png")
    }

    func testConsecutiveRecordingsDoNotOverwrite() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = makeMoment()
        let firstName = store.uniqueFileName(base: first.id, extension: "mp4")
        try store.place(temporaryFile(containing: "第一条"), as: firstName)

        // 同一秒、同一个窗口再来一次
        let second = first
        let secondName = store.uniqueFileName(base: second.id, extension: "mp4")
        try store.place(temporaryFile(containing: "第二条"), as: secondName)

        XCTAssertNotEqual(firstName, secondName)
        XCTAssertEqual(try String(contentsOf: store.fileURL(firstName), encoding: .utf8), "第一条")
        XCTAssertEqual(try String(contentsOf: store.fileURL(secondName), encoding: .utf8), "第二条")
    }

    private func temporaryFile(containing text: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try? Data(text.utf8).write(to: url)
        return url
    }

    // MARK: - 索引

    func testUpsertReplacesInsteadOfAppending() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var moment = makeMoment()
        try store.save(moment)
        moment.note = "补一句"
        moment.duration = 12
        try store.save(moment)

        let indexed = try store.loadIndex()
        XCTAssertEqual(indexed.count, 1, "同一个 id 应该就地替换，不是追加")
        XCTAssertEqual(indexed.first?.note, "补一句")
        XCTAssertEqual(indexed.first?.duration, 12)
    }

    func testIndexSurvivesRoundTrip() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var moment = makeMoment(windowTitle: "第 1 集 / 第一季: 开端")
        moment.note = "这个长镜头调度很有意思"
        moment.media = .audioOnly
        try store.save(moment)

        let loaded = try store.loadIndex().first
        XCTAssertEqual(loaded?.windowTitle, moment.windowTitle)
        XCTAssertEqual(loaded?.note, moment.note)
        XCTAssertEqual(loaded?.media, .audioOnly)
    }

    // MARK: - 文件名

    func testFolderNameStripsPathSeparatorsAndColons() throws {
        let id = MediaMoment.makeID(
            date: Date(),
            windowTitle: "第 1 集 / 第一季: 开端",
            appName: "Safari"
        )
        XCTAssertFalse(id.contains("/"))
        XCTAssertFalse(id.contains(":"))
        XCTAssertTrue(id.contains("开端"))
    }

    func testFolderNameFallsBackToAppNameWhenTitleMissing() throws {
        let id = MediaMoment.makeID(date: Date(), windowTitle: nil, appName: "Music")
        XCTAssertTrue(id.hasSuffix("Music"))
    }
}
