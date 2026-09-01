# Swipe Cleaner Persistence Implementation Plan

**Goal:** Give `CleaningSession` durable resume across app relaunches by
adding a SwiftData-backed `SessionRepositoryProtocol` implementation,
closing Milestone 3's last open item.

**Spec:** `docs/superpowers/specs/2026-09-01-swipe-cleaner-persistence-design.md`

**Branch:** `feature/swipe-cleaner`, branched from `feature/deletion-review`.

## Constraints

- Only `Persistence/SwiftDataSessionRepository.swift` and
  `Persistence/PersistedCleaningSession.swift` may `import SwiftData`.
  `CleaningSession` and every domain model stay framework-independent.
- `AppContainer.liveMock` keeps `InMemorySessionRepository`; every
  existing test keeps using it unmodified.
- No photo bytes, previews, or PhotoKit types are ever persisted — only
  the same fields `docs/PRODUCT.md`'s "Resume data" section already
  specifies.
- New tests use `ModelConfiguration(isStoredInMemoryOnly: true)`; none
  touch a real on-disk store.

## File map

- Create: `PhotoCleaner/Persistence/PersistedCleaningSession.swift`
- Create: `PhotoCleaner/Persistence/SwiftDataSessionRepository.swift`
- Modify: `PhotoCleaner/App/AppContainer.swift`
- Create: `PhotoCleanerTests/SwiftDataSessionRepositoryTests.swift`
- Modify: `docs/STATUS.md`

---

### Task 1: SwiftData-backed session repository

**Interfaces:**
- Consumes: `CleaningSession` (existing, `Codable`).
- Produces: `PersistedCleaningSession`, `SwiftDataSessionRepository`.

- [ ] **Step 1: Write failing repository tests**

```swift
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
```

- [ ] **Step 2: Run focused tests to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/SwiftDataSessionRepositoryTests test`

Expected: compilation fails because `PersistedCleaningSession` and
`SwiftDataSessionRepository` do not exist.

- [ ] **Step 3: Implement the persisted model and repository**

```swift
import Foundation
import SwiftData

@Model
final class PersistedCleaningSession {
    var payload: Data
    init(payload: Data) { self.payload = payload }
}
```

```swift
import Foundation
import SwiftData

@ModelActor
actor SwiftDataSessionRepository: SessionRepositoryProtocol {
    func loadCurrent() async throws -> CleaningSession? {
        var descriptor = FetchDescriptor<PersistedCleaningSession>()
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return nil }
        return try JSONDecoder().decode(CleaningSession.self, from: stored.payload)
    }

    func save(_ session: CleaningSession) async throws {
        try await removeCurrent()
        modelContext.insert(PersistedCleaningSession(payload: try JSONEncoder().encode(session)))
        try modelContext.save()
    }

    func removeCurrent() async throws {
        for stored in try modelContext.fetch(FetchDescriptor<PersistedCleaningSession>()) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }
}
```

- [ ] **Step 4: Run focused tests**

Run the Step 2 command again. Expected: `** TEST SUCCEEDED **`, all four
tests pass.

- [ ] **Step 5: Wire `AppContainer.live` to the real repository**

```swift
import SwiftData

private static let sessionModelContainer: ModelContainer = {
    do {
        return try ModelContainer(for: PersistedCleaningSession.self)
    } catch {
        fatalError("Failed to create session ModelContainer: \(error)")
    }
}()

static var live: AppContainer {
    AppContainer(
        library: PhotoKitPhotoLibraryService(),
        sessions: SwiftDataSessionRepository(modelContainer: sessionModelContainer)
    )
}
```

`liveMock` is untouched — it keeps `InMemorySessionRepository`.

- [ ] **Step 6: Run the full suite and static safety checks**

Run: `rg -n '^import SwiftData' PhotoCleaner/Domain PhotoCleaner/Features PhotoCleaner/Services`

Expected: no output — SwiftData stays confined to `Persistence/` and
`App/AppContainer.swift`.

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build`

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test`

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`, with every
prior test still passing alongside the four new ones.

- [ ] **Step 7: Update status and commit**

Update `docs/STATUS.md`: move Milestone 3 to complete, add a verification
entry with the exact build/test results and new test count.

```bash
git add PhotoCleaner/Persistence PhotoCleaner/App/AppContainer.swift PhotoCleanerTests/SwiftDataSessionRepositoryTests.swift docs/STATUS.md docs/superpowers/plans/2026-09-01-swipe-cleaner-persistence.md docs/superpowers/specs/2026-09-01-swipe-cleaner-persistence-design.md
git commit -m "feat: persist cleaning sessions with SwiftData"
```

## Remaining manual check

Install the app on the `PhotoCleaner iPhone 13 mini` simulator (or a
device), start cleaning a source, force-quit before closing the Cleaner,
relaunch, and confirm Home offers "Continue" and the Cleaner resumes at
the same position and pending-deletion queue.
