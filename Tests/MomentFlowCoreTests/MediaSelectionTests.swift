import XCTest
@testable import MomentFlowCore

final class MediaSelectionTests: XCTestCase {

    func testFileExtensionFollowsVideoPresence() {
        XCTAssertEqual(MediaSelection.videoWithAudio.fileExtension, "mp4")
        XCTAssertEqual(MediaSelection.videoOnly.fileExtension, "mp4")
        XCTAssertEqual(MediaSelection.audioOnly.fileExtension, "m4a")
    }

    func testNothingSelectedIsInvalid() {
        XCTAssertFalse(MediaSelection(video: false, systemAudio: false).isValid)
        XCTAssertTrue(MediaSelection.audioOnly.isValid)
        XCTAssertTrue(MediaSelection.videoOnly.isValid)
    }

    func testSelectionSurvivesRoundTrip() throws {
        // 要跟着 moment.json 一起存下来，所以必须能序列化。
        let data = try JSONEncoder().encode(MediaSelection.audioOnly)
        let decoded = try JSONDecoder().decode(MediaSelection.self, from: data)
        XCTAssertEqual(decoded, MediaSelection.audioOnly)
    }

    func testLegacyDataWithoutMicrophoneDecodesAsOff() throws {
        // 旧版本的索引里没有 microphone 字段，读出来必须是关，
        // 否则老素材会被当成"录了麦克风"。
        let json = #"{"video":true,"systemAudio":true}"#
        let decoded = try JSONDecoder().decode(MediaSelection.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.video)
        XCTAssertTrue(decoded.systemAudio)
        XCTAssertFalse(decoded.microphone)
    }

    func testMicrophoneIsAdditive() {
        let selection = MediaSelection(video: true, systemAudio: true, microphone: true)
        XCTAssertTrue(selection.isValid)
        XCTAssertEqual(selection.summary, "画面 + 系统声音 + 麦克风")
    }

    func testMicrophoneAloneIsNotEnough() {
        // 麦克风是叠加项，单独勾麦克风不应该能开始录制。
        let selection = MediaSelection(video: false, systemAudio: false, microphone: true)
        XCTAssertFalse(selection.isValid)
    }
}
