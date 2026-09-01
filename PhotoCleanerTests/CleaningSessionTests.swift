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

    func testIsCompleteReflectsWhetherEveryAssetHasBeenDecided() throws {
        var session = CleaningSession.fixture(assetIDs: ["a", "b"])
        XCTAssertFalse(session.isComplete)

        try session.decide(.keep, assetID: "a")
        XCTAssertFalse(session.isComplete)

        try session.decide(.pendingDelete, assetID: "b")
        XCTAssertTrue(session.isComplete)
    }

    func testEmptySessionIsImmediatelyComplete() {
        XCTAssertTrue(CleaningSession.fixture(assetIDs: []).isComplete)
    }

    func testRestoreAllPendingDeletionsClearsQueueAndDecisions() throws {
        var session = CleaningSession.fixture(assetIDs: ["a", "b", "c"])
        try session.decide(.pendingDelete, assetID: "a")
        try session.decide(.keep, assetID: "b")
        try session.decide(.pendingDelete, assetID: "c")

        session.restoreAllPendingDeletions()

        XCTAssertTrue(session.pendingDeletionIDs.isEmpty)
        XCTAssertNil(session.decisions["a"])
        XCTAssertNil(session.decisions["c"])
        XCTAssertEqual(session.decisions["b"], .keep)
    }

    func testRestoreAllPendingDeletionsOnEmptyQueueDoesNothing() {
        var session = CleaningSession.fixture(assetIDs: ["a"])
        let before = session

        session.restoreAllPendingDeletions()

        XCTAssertEqual(session, before)
    }

    func testMissingAssetIsRecordedAndSkipped() {
        var session = CleaningSession.fixture(assetIDs: ["a", "b"])

        session.skipUnavailableAsset(id: "a")

        XCTAssertEqual(session.unavailableAssetIDs, ["a"])
        XCTAssertEqual(session.currentPosition, 1)
    }
}
