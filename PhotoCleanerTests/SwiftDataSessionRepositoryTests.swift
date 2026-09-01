import XCTest
import SwiftData
@testable import PhotoCleaner

final class SwiftDataSessionRepositoryTests: XCTestCase {
    private func makeRepository() throws -> SwiftDataSessionRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedCleaningSession.self, configurations: configuration)
        return SwiftDataSessionRepository(modelContainer: container)
    }

    func testLoadCurrentReturnsNilWhenNothingWasEverSaved() async throws {
        let repository = try makeRepository()
        let loaded = try await repository.loadCurrent()
        XCTAssertNil(loaded)
    }

    func testRoundTripsSessionAcrossRepositoryInstancesSharingAContainer() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedCleaningSession.self, configurations: configuration)
        let session = CleaningSession.fixturePendingDeletion(ids: ["a", "b"])

        try await SwiftDataSessionRepository(modelContainer: container).save(session)
        let loaded = try await SwiftDataSessionRepository(modelContainer: container).loadCurrent()

        XCTAssertEqual(loaded?.orderedAssetIDs, ["a", "b"])
        XCTAssertEqual(loaded?.pendingDeletionIDs, ["a", "b"])
    }

    func testSavingReplacesThePreviousSessionRatherThanAccumulating() async throws {
        let repository = try makeRepository()
        try await repository.save(.fixture(assetIDs: ["a"]))
        try await repository.save(.fixture(assetIDs: ["b", "c"]))

        let loaded = try await repository.loadCurrent()
        XCTAssertEqual(loaded?.orderedAssetIDs, ["b", "c"])
    }

    func testRemoveCurrentClearsTheStoredSession() async throws {
        let repository = try makeRepository()
        try await repository.save(.fixture(assetIDs: ["a"]))

        try await repository.removeCurrent()

        let loaded = try await repository.loadCurrent()
        XCTAssertNil(loaded)
    }
}
