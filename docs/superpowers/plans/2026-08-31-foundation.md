# Photo Cleaner Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iPhone-only SwiftUI foundation whose complete navigation and cleaning-session behavior run safely against deterministic mock data.

**Architecture:** Feature-based MVVM keeps SwiftUI views behind `@MainActor` view models. `AppContainer` injects protocol-backed photo-library and session dependencies; domain values contain no PhotoKit or SwiftData types, and the Milestone 1 implementations are mock/in-memory only.

**Tech Stack:** Swift 6, SwiftUI, XCTest, native Xcode project, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-31-foundation-design.md`

## Global Constraints

- Target iPhone only with `TARGETED_DEVICE_FAMILY = 1`.
- Use iOS 17.0 or newer and Swift 6 language mode.
- Check in a native `PhotoCleaner.xcodeproj`; add no project generator or third-party dependency.
- Use `com.example.PhotoCleaner` as the initial bundle identifier.
- Do not import PhotoKit or SwiftData in Milestone 1.
- Do not request authorization or mutate a real photo library.
- A keep or pending-delete decision must never call `deleteAssets(ids:)`.
- Persist no photo bytes; mock previews use SF Symbol names only.
- Keep observable UI state and view models on the main actor.
- Full Xcode is not currently installed or selected; do not report iOS build/test success until `xcodebuild -version` succeeds.

## File map

- `PhotoCleaner.xcodeproj/project.pbxproj`: native app/test targets, iPhone-only build settings, source synchronization, shared scheme.
- `PhotoCleaner/App/PhotoCleanerApp.swift`: composition root and root scene.
- `PhotoCleaner/App/AppContainer.swift`: dependency ownership and view-model factories.
- `PhotoCleaner/App/AppRouter.swift`: typed routes and navigation path.
- `PhotoCleaner/Domain/Models/*.swift`: framework-independent access, source, asset, decision, and session values.
- `PhotoCleaner/Domain/Protocols/*.swift`: photo-library and session repository boundaries.
- `PhotoCleaner/Services/MockPhotoLibraryService.swift`: deterministic mock content, injected failures, and call recording.
- `PhotoCleaner/Persistence/InMemorySessionRepository.swift`: actor-isolated ephemeral session storage.
- `PhotoCleaner/Features/*`: one view and one focused main-actor view model per implemented feature.
- `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift`: shared spacing and card styling only.
- `PhotoCleaner/Resources/Assets.xcassets`: minimal app asset catalog.
- `PhotoCleanerTests/*Tests.swift`: domain, service, view-model, navigation, and safety tests.

---

### Task 1: Native project and composition smoke test

**Files:**
- Create: `PhotoCleaner.xcodeproj/project.pbxproj`
- Create: `PhotoCleaner.xcodeproj/xcshareddata/xcschemes/PhotoCleaner.xcscheme`
- Create: `PhotoCleaner/Info.plist`
- Create: `PhotoCleaner/App/PhotoCleanerApp.swift`
- Create: `PhotoCleaner/App/RootView.swift`
- Create: `PhotoCleaner/Resources/Assets.xcassets/Contents.json`
- Create: `PhotoCleaner/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `PhotoCleanerTests/AppLaunchTests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `PhotoCleanerApp`, `RootView`, app target `PhotoCleaner`, test target `PhotoCleanerTests`, shared scheme `PhotoCleaner`.

- [ ] **Step 1: Write the composition smoke test**

```swift
import XCTest
@testable import PhotoCleaner

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testRootViewCanBeConstructed() {
        _ = RootView()
    }
}
```

- [ ] **Step 2: Create the native project and minimal app**

Configure the project with two targets, automatic file-system-synchronized source groups, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 6.0`, `TARGETED_DEVICE_FAMILY = 1`, app identifier `com.example.PhotoCleaner`, test identifier `com.example.PhotoCleanerTests`, and `CODE_SIGNING_ALLOWED = NO` for simulator-friendly CLI builds.

```swift
import SwiftUI

@main
struct PhotoCleanerApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack { Text("Photo Cleaner") }
    }
}
```

- [ ] **Step 3: Validate project structure before attempting Xcode**

Run: `plutil -lint PhotoCleaner/Info.plist PhotoCleaner.xcodeproj/xcshareddata/xcschemes/PhotoCleaner.xcscheme`

Expected: both files report `OK`.

Run: `rg -n 'IPHONEOS_DEPLOYMENT_TARGET = 17.0|SWIFT_VERSION = 6.0|TARGETED_DEVICE_FAMILY = 1|PhotoCleanerTests' PhotoCleaner.xcodeproj/project.pbxproj`

Expected: every required setting and the test target are present.

- [ ] **Step 4: Attempt the smoke test without overstating the result**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' test`

Expected on the current machine: fail before compilation because the selected developer directory contains Command Line Tools only. If full Xcode becomes available, expected result is `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PhotoCleaner.xcodeproj PhotoCleaner PhotoCleanerTests/AppLaunchTests.swift
git commit -m "build: create iPhone app and test targets"
```

### Task 2: Domain values and session decision engine

**Files:**
- Create: `PhotoCleaner/Domain/Models/PhotoAccessStatus.swift`
- Create: `PhotoCleaner/Domain/Models/CleaningSource.swift`
- Create: `PhotoCleaner/Domain/Models/PhotoAsset.swift`
- Create: `PhotoCleaner/Domain/Models/PhotoDecision.swift`
- Create: `PhotoCleaner/Domain/Models/CleaningSession.swift`
- Create: `PhotoCleanerTests/TestFixtures.swift`
- Create: `PhotoCleanerTests/CleaningSessionTests.swift`

**Interfaces:**
- Consumes: Foundation `UUID` and `Date` only.
- Produces: `PhotoAccessStatus`, `TimelineGroup`, `PhotoAlbum`, `CleaningSource`, `PhotoAsset`, `PhotoDecision`, `CleaningSession`, `CleaningSession.decide(_:assetID:)`, `undoLastDecision()`, and `skipUnavailableAsset(id:)`.

- [ ] **Step 1: Write failing session behavior tests**

```swift
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
```

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PhotoCleanerTests/CleaningSessionTests test`

Expected with Xcode: compilation fails because the domain types do not exist.

- [ ] **Step 3: Implement the minimal framework-independent domain**

Use these exact declarations:

```swift
enum PhotoAccessStatus: String, Codable, Sendable { case notDetermined, limited, authorized, denied, restricted }
struct TimelineGroup: Identifiable, Hashable, Codable, Sendable { let id: String; let title: String; let interval: DateInterval; let photoCount: Int }
struct PhotoAlbum: Identifiable, Hashable, Codable, Sendable { let id: String; let title: String; let photoCount: Int }
enum CleaningSource: Hashable, Codable, Sendable { case timeline(TimelineGroup); case album(PhotoAlbum) }
struct PhotoAsset: Identifiable, Hashable, Codable, Sendable { let id: String; let creationDate: Date?; var isFavorite: Bool; let previewSymbolName: String }
enum PhotoDecision: String, Codable, Sendable { case keep, pendingDelete }
enum SessionDecisionError: Error, Equatable { case unknownAsset, outOfOrderAsset }
```

`CleaningSession` stores `id`, `source`, `orderedAssetIDs`, `currentPosition`, `decisions`, `pendingDeletionIDs`, `unavailableAssetIDs`, `createdAt`, `updatedAt`, and a private undo history. `decide` accepts only the identifier at `currentPosition`, updates the decision and queue, advances once, and timestamps the mutation. `undoLastDecision` removes the latest decision and queue membership and restores its index. `skipUnavailableAsset` records a known identifier once and advances when it is current.

Add test-only factories with exact signatures:

```swift
extension CleaningSession {
    static func fixture(assetIDs: [String]) -> CleaningSession
    static func fixturePendingDeletion(ids: [String]) -> CleaningSession
}
```

`fixture(assetIDs:)` uses album `PhotoAlbum(id: "album", title: "Mock Album", photoCount: assetIDs.count)`, position zero, empty decisions/queues, and a fixed date. `fixturePendingDeletion(ids:)` starts from that value and applies `.pendingDelete` to each identifier in order.

- [ ] **Step 4: Run focused tests**

Run the Step 2 command again.

Expected with Xcode: `** TEST SUCCEEDED **` and all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add PhotoCleaner/Domain/Models PhotoCleanerTests/TestFixtures.swift PhotoCleanerTests/CleaningSessionTests.swift
git commit -m "feat: add cleaning session domain model"
```

### Task 3: Service protocols and safe mock implementations

**Files:**
- Create: `PhotoCleaner/Domain/Protocols/PhotoLibraryServiceProtocol.swift`
- Create: `PhotoCleaner/Domain/Protocols/SessionRepositoryProtocol.swift`
- Create: `PhotoCleaner/Services/MockPhotoLibraryService.swift`
- Create: `PhotoCleaner/Persistence/InMemorySessionRepository.swift`
- Create: `PhotoCleanerTests/MockServicesTests.swift`

**Interfaces:**
- Consumes: all Task 2 domain values.
- Produces: `PhotoLibraryServiceProtocol`, `SessionRepositoryProtocol`, `MockPhotoLibraryService`, `MockPhotoLibraryError`, and actor `InMemorySessionRepository`.

- [ ] **Step 1: Write failing mock and repository tests**

```swift
import XCTest
@testable import PhotoCleaner

final class MockServicesTests: XCTestCase {
    func testRepositoryRoundTripsValueWithoutPhotoData() async throws {
        let repository = InMemorySessionRepository()
        let session = CleaningSession.fixture(assetIDs: ["a"])
        try await repository.save(session)
        let loaded = try await repository.loadCurrent()
        XCTAssertEqual(loaded?.orderedAssetIDs, ["a"])
    }

    func testMockRecordsDeleteOnlyWhenExplicitlyRequested() async throws {
        let service = MockPhotoLibraryService.sample
        _ = try await service.fetchAssets(for: .album(.init(id: "album", title: "Mock Album", photoCount: 3)))
        XCTAssertEqual(await service.deletedIDBatches, [])
        try await service.deleteAssets(ids: ["asset-1"])
        XCTAssertEqual(await service.deletedIDBatches, [["asset-1"]])
    }
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PhotoCleanerTests/MockServicesTests test`

Expected with Xcode: compilation fails because the protocols and implementations do not exist.

- [ ] **Step 3: Define the service boundaries**

```swift
protocol PhotoLibraryServiceProtocol: Sendable {
    func requestAuthorization() async -> PhotoAccessStatus
    func fetchTimelineGroups() async throws -> [TimelineGroup]
    func fetchAlbums() async throws -> [PhotoAlbum]
    func fetchAssets(for source: CleaningSource) async throws -> [PhotoAsset]
    func setFavorite(_ favorite: Bool, assetID: String) async throws
    func addAsset(_ assetID: String, toAlbum albumID: String) async throws
    func createAlbum(named name: String) async throws -> PhotoAlbum
    func deleteAssets(ids: [String]) async throws
}

protocol SessionRepositoryProtocol: Sendable {
    func loadCurrent() async throws -> CleaningSession?
    func save(_ session: CleaningSession) async throws
    func removeCurrent() async throws
}
```

- [ ] **Step 4: Implement deterministic actor-backed mocks**

`MockPhotoLibraryService` is an actor with sample timeline groups, albums, and assets; configurable `PhotoAccessStatus`; `MockPhotoLibraryError.forcedFailure`; and call-recording arrays for favorite, album, create, and delete operations. `InMemorySessionRepository` is an actor holding one optional session. Neither implementation imports PhotoKit, SwiftData, or UIKit.

- [ ] **Step 5: Run focused tests and commit**

Run the Step 2 command. Expected with Xcode: `** TEST SUCCEEDED **`.

```bash
git add PhotoCleaner/Domain/Protocols PhotoCleaner/Services PhotoCleaner/Persistence PhotoCleanerTests/MockServicesTests.swift
git commit -m "feat: add injectable mock services"
```

### Task 4: Typed routing, dependency container, and Home

**Files:**
- Create: `PhotoCleaner/App/AppRoute.swift`
- Create: `PhotoCleaner/App/AppRouter.swift`
- Create: `PhotoCleaner/App/AppContainer.swift`
- Modify: `PhotoCleaner/App/PhotoCleanerApp.swift`
- Modify: `PhotoCleaner/App/RootView.swift`
- Create: `PhotoCleaner/Features/Home/HomeView.swift`
- Create: `PhotoCleaner/Features/Home/HomeViewModel.swift`
- Create: `PhotoCleanerTests/HomeViewModelTests.swift`

**Interfaces:**
- Consumes: `PhotoLibraryServiceProtocol`, `SessionRepositoryProtocol`, and Task 2 models.
- Produces: `AppRoute`, `AppRouter.path`, `AppRouter.navigate(to:)`, `AppRouter.popToRoot()`, `AppContainer.liveMock`, `HomeViewModel.load()`, and the navigation composition root.

- [ ] **Step 1: Write failing Home state and route tests**

```swift
@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLoadShowsAccessAndSavedSession() async {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository(initial: .fixture(assetIDs: ["a"]))
        let model = HomeViewModel(library: library, sessions: repository)
        await model.load()
        XCTAssertEqual(model.accessStatus, .limited)
        XCTAssertNotNil(model.savedSession)
    }

    func testRoutesRemainStronglyTyped() {
        let router = AppRouter()
        router.navigate(to: .sourcePicker)
        XCTAssertEqual(router.path, [.sourcePicker])
    }
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PhotoCleanerTests/HomeViewModelTests test`

Expected with Xcode: compilation fails because routing and Home types do not exist.

- [ ] **Step 3: Implement routing and dependency composition**

```swift
enum AppRoute: Hashable {
    case sourcePicker
    case cleaner(CleaningSource)
    case deletionReview
    case settings
}

@MainActor @Observable
final class AppRouter {
    var path: [AppRoute] = []
    func navigate(to route: AppRoute) { path.append(route) }
    func popToRoot() { path.removeAll() }
}
```

`AppContainer` holds `any PhotoLibraryServiceProtocol` and `any SessionRepositoryProtocol`, exposes `liveMock`, and creates view models. `RootView` owns the router, renders `HomeView`, and maps every route through `navigationDestination(for:)`. `PhotoCleanerApp` owns one container for the scene lifetime.

- [ ] **Step 4: Implement Home loading and accessible actions**

`HomeViewModel` exposes `isLoading`, `accessStatus`, `savedSession`, `pendingDeletionCount`, and `errorMessage`. `load()` independently requests mock authorization and loads the current session, setting a recoverable message on error. `HomeView` exposes Continue only when a session exists, plus Clean by Date, Clean an Album, Pending Deletion Review, and Settings buttons.

- [ ] **Step 5: Run focused tests and commit**

Run the Step 2 command. Expected with Xcode: `** TEST SUCCEEDED **`.

```bash
git add PhotoCleaner/App PhotoCleaner/Features/Home PhotoCleanerTests/HomeViewModelTests.swift
git commit -m "feat: add typed navigation and home screen"
```

### Task 5: Source selection, Cleaner, and save/undo flow

**Files:**
- Create: `PhotoCleaner/Features/SourcePicker/SourcePickerView.swift`
- Create: `PhotoCleaner/Features/SourcePicker/SourcePickerViewModel.swift`
- Create: `PhotoCleaner/Features/Cleaner/CleanerView.swift`
- Create: `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift`
- Create: `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift`
- Modify: `PhotoCleaner/App/AppContainer.swift`
- Modify: `PhotoCleaner/App/RootView.swift`
- Create: `PhotoCleanerTests/SourcePickerViewModelTests.swift`
- Create: `PhotoCleanerTests/CleanerViewModelTests.swift`

**Interfaces:**
- Consumes: Task 2 models, Task 3 services, and Task 4 routing.
- Produces: `SourcePickerViewModel.load()`, `CleanerViewModel.load()`, `keepCurrent()`, `queueCurrentForDeletion()`, `undo()`, and `save()`.

- [ ] **Step 1: Write failing source and cleaner tests**

```swift
@MainActor
final class CleanerViewModelTests: XCTestCase {
    func testQueueAndUndoNeverCallDelete() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let model = CleanerViewModel(source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)), library: library, sessions: repository)
        await model.load()
        await model.queueCurrentForDeletion()
        model.undo()
        XCTAssertTrue(await library.deletedIDBatches.isEmpty)
        XCTAssertEqual(model.progressText, "1 of 3")
    }

    func testSaveCanBeLoadedByNewViewModel() async throws {
        let library = MockPhotoLibraryService.sample
        let repository = InMemorySessionRepository()
        let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
        let first = CleanerViewModel(source: source, library: library, sessions: repository)
        await first.load()
        await first.keepCurrent()
        try await first.save()
        let second = CleanerViewModel(source: source, library: library, sessions: repository)
        await second.load()
        XCTAssertEqual(second.session.currentPosition, 1)
    }
}
```

`SourcePickerViewModelTests` verifies timeline and album success, empty results, forced errors, and that selecting a source reports its exact count.

- [ ] **Step 2: Run both test classes to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PhotoCleanerTests/SourcePickerViewModelTests -only-testing:PhotoCleanerTests/CleanerViewModelTests test`

Expected with Xcode: compilation fails because the feature types do not exist.

- [ ] **Step 3: Implement source selection states**

`SourcePickerViewModel.State` has `.loading`, `.content(timeline:albums:)`, `.empty`, and `.failed(message:)`. It fetches timeline groups and albums concurrently with `async let`, and exposes source selection without starting a session. The view uses a segmented timeline/album display and shows each source's photo count before its Start button.

- [ ] **Step 4: Implement safe cleaner behavior**

`CleanerViewModel.load()` resumes a matching stored session or fetches source assets and creates a new ordered session. It skips identifiers absent from fetched assets. Keep and pending-delete call only `CleaningSession.decide`; `undo` calls only `undoLastDecision`; `save` calls only the repository. The view shows mock symbol preview, creation date, favorite status, progress, accessible Keep/Delete buttons, equivalent accessibility actions, Undo, an Album button labeled as unavailable in Milestone 1, and Close/Save.

- [ ] **Step 5: Run focused tests and commit**

Run the Step 2 command. Expected with Xcode: `** TEST SUCCEEDED **`.

```bash
git add PhotoCleaner/Features/SourcePicker PhotoCleaner/Features/Cleaner PhotoCleaner/DesignSystem PhotoCleaner/App PhotoCleanerTests/SourcePickerViewModelTests.swift PhotoCleanerTests/CleanerViewModelTests.swift
git commit -m "feat: add mock source and cleaner flows"
```

### Task 6: Deletion Review, Settings, safety audit, and final verification

**Files:**
- Create: `PhotoCleaner/Features/DeletionReview/DeletionReviewView.swift`
- Create: `PhotoCleaner/Features/DeletionReview/DeletionReviewViewModel.swift`
- Create: `PhotoCleaner/Features/Settings/SettingsView.swift`
- Create: `PhotoCleaner/Features/Settings/SettingsViewModel.swift`
- Modify: `PhotoCleaner/App/AppContainer.swift`
- Modify: `PhotoCleaner/App/RootView.swift`
- Create: `PhotoCleanerTests/DeletionReviewViewModelTests.swift`
- Create: `PhotoCleanerTests/SafetyInvariantTests.swift`

**Interfaces:**
- Consumes: session repository, mock library, typed routes.
- Produces: `DeletionReviewViewModel.load()`, `restore(id:)`, `selectAll()`, `deselectAll()`, `cancel()`, `confirmMockDeletion()`, and `SettingsViewModel.load()`.

- [ ] **Step 1: Write failing review and cross-feature safety tests**

```swift
@MainActor
final class DeletionReviewViewModelTests: XCTestCase {
    func testRestoreRemovesOnlyRequestedIdentifierAndSavesQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a", "b"]))
        let model = DeletionReviewViewModel(sessions: repository)
        await model.load()
        try await model.restore(id: "a")
        XCTAssertEqual(model.pendingIDs, ["b"])
        XCTAssertEqual(try await repository.loadCurrent()?.pendingDeletionIDs, ["b"])
    }

    func testCancelRetainsQueue() async throws {
        let repository = InMemorySessionRepository(initial: .fixturePendingDeletion(ids: ["a"]))
        let model = DeletionReviewViewModel(sessions: repository)
        await model.load()
        model.cancel()
        XCTAssertEqual(try await repository.loadCurrent()?.pendingDeletionIDs, ["a"])
    }
}
```

`SafetyInvariantTests` executes keep, queue, undo, close/save, restore, select all, deselect all, and cancel against one recording mock, then asserts `deletedIDBatches.isEmpty`.

- [ ] **Step 2: Run focused tests to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PhotoCleanerTests/DeletionReviewViewModelTests -only-testing:PhotoCleanerTests/SafetyInvariantTests test`

Expected with Xcode: compilation fails because review types do not exist.

- [ ] **Step 3: Implement Deletion Review and Settings**

Deletion Review loads the exact pending identifiers from the repository, renders them in an adaptive grid, allows individual restoration and selection changes, and persists restoration. Cancel navigates back without mutation. `confirmMockDeletion()` presents a non-destructive Milestone 1 message and does not call `deleteAssets`. Settings loads and labels the mock authorization state, including limited, denied, and restricted states.

- [ ] **Step 4: Run all static safety checks**

Run: `rg -n '^import (PhotoKit|SwiftData)' PhotoCleaner PhotoCleanerTests`

Expected: no output.

Run: `rg -n 'deleteAssets' PhotoCleaner/Features PhotoCleaner/App`

Expected: no output.

Run: `plutil -lint PhotoCleaner/Info.plist PhotoCleaner.xcodeproj/xcshareddata/xcschemes/PhotoCleaner.xcscheme && git diff --check`

Expected: both plist/XML files report `OK` and `git diff --check` prints nothing.

- [ ] **Step 5: Run the complete build and test suite**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' build`

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=iPhone 16' test`

Expected with full Xcode and the named simulator: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`. On the current machine, report the developer-directory error exactly and leave both results unverified.

- [ ] **Step 6: Commit**

```bash
git add PhotoCleaner/Features/DeletionReview PhotoCleaner/Features/Settings PhotoCleaner/App PhotoCleanerTests
git commit -m "feat: complete safe mock foundation"
```

## Remaining Xcode checks

After installing/selecting full Xcode, use `xcrun simctl list devices available` to choose an installed iPhone simulator if iPhone 16 is absent. Launch the app and manually verify every Home route, limited/denied labels, source count, Keep/Delete accessibility actions, Undo, Close/Save and resume, exact review queue, cancel retention, Dynamic Type at the largest accessibility size, VoiceOver focus order, portrait and landscape layouts, and absence of photo permission prompts.
