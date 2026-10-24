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
}
