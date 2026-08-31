import XCTest
@testable import PhotoCleaner

final class CleaningSessionTests: XCTestCase {
    func testPendingDeleteQueuesIdentifierWithoutRemovingIt() throws {
        var session = CleaningSession.fixture(assetIDs: ["a", "b"])

        try session.decide(.pendingDelete, assetID: "a")

        XCTAssertEqual(session.decisions["a"], .pendingDelete)
        XCTAssertEqual(session.pendingDeletionIDs, ["a"])
        XCTAssertEqual(session.currentPosition, 1)
    }

    func testUndoRestoresPreviousPositionAndQueue() throws {
        var session = CleaningSession.fixture(assetIDs: ["a", "b"])
        try session.decide(.pendingDelete, assetID: "a")

        XCTAssertEqual(session.undoLastDecision(), "a")

        XCTAssertNil(session.decisions["a"])
        XCTAssertTrue(session.pendingDeletionIDs.isEmpty)
        XCTAssertEqual(session.currentPosition, 0)
    }

    func testMissingAssetIsRecordedAndSkipped() {
        var session = CleaningSession.fixture(assetIDs: ["a", "b"])

        session.skipUnavailableAsset(id: "a")

        XCTAssertEqual(session.unavailableAssetIDs, ["a"])
        XCTAssertEqual(session.currentPosition, 1)
    }
}
