# Favorites and Albums Implementation Plan

**Goal:** Deliver Milestone 4 — optimistic favorite toggling from the
Cleaner, and a searchable album picker (existing-membership checkmarks,
add, create) reachable from the Cleaner's Album button.

**Spec:** `docs/superpowers/specs/2026-09-01-favorites-albums-design.md`

**Branch:** `feature/favorites-albums`, branched from `main` (which
already includes Milestones 1–3 and the deletion-review carry-forward
fix).

## Constraints

- Only `Persistence/` and `App/AppContainer.swift` may `import SwiftData`
  (unchanged from prior milestones) — this milestone touches neither.
- `deleteAssets` stays called from exactly one place
  (`DeletionReviewViewModel.confirmDeletion()`); nothing here adds a
  second call site.
- The album picker is a sheet owned by the Cleaner, not a new `AppRoute`
  case — it has no reason to be deep-linkable or part of the back stack.
- Every optimistic mutation (favorite, album add) rolls back its local
  state on failure and surfaces a recoverable error message, matching
  the existing `saveErrorMessage`/`deletionErrorMessage` pattern.

## File map

- Modify: `PhotoCleaner/Domain/Protocols/PhotoLibraryServiceProtocol.swift`
- Modify: `PhotoCleaner/Services/MockPhotoLibraryService.swift`
- Modify: `PhotoCleaner/Services/PhotoKit/PhotoKitPhotoLibraryService.swift`
- Modify: `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift`
- Modify: `PhotoCleaner/Features/Cleaner/CleanerView.swift`
- Create: `PhotoCleaner/Features/AlbumPicker/AlbumPickerViewModel.swift`
- Create: `PhotoCleaner/Features/AlbumPicker/AlbumPickerView.swift`
- Modify: `PhotoCleanerTests/MockServicesTests.swift`
- Modify: `PhotoCleanerTests/CleanerViewModelTests.swift`
- Create: `PhotoCleanerTests/AlbumPickerViewModelTests.swift`
- Modify: `docs/STATUS.md`

---

### Task 1: Protocol, mock, and PhotoKit implementations

**Interfaces:**
- Consumes: existing `setFavorite`/`addAsset`/`createAlbum` signatures.
- Produces: `PhotoLibraryServiceProtocol.albumIDs(containingAssetID:)`,
  real `PhotoKitPhotoLibraryService` implementations, mock membership
  tracking.

- [ ] **Step 1: Write failing mock-service tests**

```swift
func testAddAssetRecordsAssignmentAndReflectsMembership() async throws {
    let service = MockPhotoLibraryService.sample
    var membership = try await service.albumIDs(containingAssetID: "asset-1")
    XCTAssertTrue(membership.isEmpty)

    try await service.addAsset("asset-1", toAlbum: "album")

    membership = try await service.albumIDs(containingAssetID: "asset-1")
    XCTAssertEqual(membership, ["album"])
    let assignments = await service.albumAssignments
    XCTAssertEqual(assignments, [.init(assetID: "asset-1", albumID: "album")])
}

func testSetAlbumMembershipSeedsWithoutRecordingAnAssignment() async throws {
    let service = MockPhotoLibraryService.sample
    await service.setAlbumMembership(["asset-1"], for: "album")

    let membership = try await service.albumIDs(containingAssetID: "asset-1")
    XCTAssertEqual(membership, ["album"])
    let assignments = await service.albumAssignments
    XCTAssertTrue(assignments.isEmpty)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/MockServicesTests test`

Expected: compilation fails — `albumIDs(containingAssetID:)` and
`setAlbumMembership(_:for:)` do not exist yet.

- [ ] **Step 3: Add the protocol method and mock tracking**

```swift
protocol PhotoLibraryServiceProtocol: Sendable {
    // ...existing members...
    func albumIDs(containingAssetID assetID: String) async throws -> Set<String>
}
```

In `MockPhotoLibraryService`, add
`private var assetIDsByAlbumID: [String: Set<String>] = [:]`, implement
`albumIDs(containingAssetID:)` by scanning it, update `addAsset` to
insert into it, and add `func setAlbumMembership(_ assetIDs: Set<String>, for albumID: String)`.

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command again. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Implement the real PhotoKit methods**

```swift
func setFavorite(_ favorite: Bool, assetID: String) async throws {
    try Task.checkCancellation()
    guard let asset = fetchAsset(byLocalIdentifier: assetID) else {
        throw PhotoKitServiceError.assetNotFound
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = favorite
        } completionHandler: { success, error in
            success ? continuation.resume() : continuation.resume(throwing: error ?? PhotoKitServiceError.favoriteUpdateFailed)
        }
    }
}

func addAsset(_ assetID: String, toAlbum albumID: String) async throws {
    try Task.checkCancellation()
    guard let asset = fetchAsset(byLocalIdentifier: assetID) else {
        throw PhotoKitServiceError.assetNotFound
    }
    guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else {
        throw PhotoKitServiceError.albumNotFound
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets([asset] as NSArray)
        } completionHandler: { success, error in
            success ? continuation.resume() : continuation.resume(throwing: error ?? PhotoKitServiceError.albumAssignmentFailed)
        }
    }
}

func createAlbum(named name: String) async throws -> PhotoAlbum {
    try Task.checkCancellation()
    var placeholder: PHObjectPlaceholder?
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        } completionHandler: { success, error in
            success ? continuation.resume() : continuation.resume(throwing: error ?? PhotoKitServiceError.albumCreationFailed)
        }
    }
    guard let identifier = placeholder?.localIdentifier else {
        throw PhotoKitServiceError.albumCreationFailed
    }
    return PhotoAlbum(id: identifier, title: name, photoCount: 0)
}

func albumIDs(containingAssetID assetID: String) async throws -> Set<String> {
    try Task.checkCancellation()
    guard let asset = fetchAsset(byLocalIdentifier: assetID) else { return [] }
    let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
    var ids: Set<String> = []
    collections.enumerateObjects { collection, _, _ in
        guard collection.assetCollectionSubtype == .albumRegular else { return }
        ids.insert(collection.localIdentifier)
    }
    return ids
}
```

Add `case assetNotFound`, `case favoriteUpdateFailed`,
`case albumAssignmentFailed`, `case albumCreationFailed` to
`PhotoKitServiceError`.

- [ ] **Step 6: Build and commit**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build`

Expected: `** BUILD SUCCEEDED **`.

```bash
git add PhotoCleaner/Domain/Protocols/PhotoLibraryServiceProtocol.swift PhotoCleaner/Services PhotoCleanerTests/MockServicesTests.swift
git commit -m "feat: implement real favorite and album mutations"
```

### Task 2: Favorite toggle and album picker UI

**Interfaces:**
- Consumes: Task 1's protocol and service implementations.
- Produces: `CleanerViewModel.toggleFavorite()`,
  `CleanerViewModel.makeAlbumPickerViewModel(assetID:)`,
  `AlbumPickerViewModel`, `AlbumPickerView`.

- [ ] **Step 1: Write failing view-model tests**

```swift
func testToggleFavoriteIsOptimisticAndPersists() async throws {
    let library = MockPhotoLibraryService.sample
    let model = CleanerViewModel(source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)), library: library, sessions: InMemorySessionRepository())
    await model.load()
    XCTAssertEqual(model.currentAsset?.isFavorite, false)

    await model.toggleFavorite()

    XCTAssertEqual(model.currentAsset?.isFavorite, true)
    let mutations = await library.favoriteMutations
    XCTAssertEqual(mutations, [.init(assetID: "asset-1", isFavorite: true)])
}

func testFailedFavoriteToggleRollsBackAndShowsError() async throws {
    let library = MockPhotoLibraryService.sample
    await library.setForcedError(.forcedFailure)
    let model = CleanerViewModel(source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)), library: library, sessions: InMemorySessionRepository())
    await model.load()

    await model.toggleFavorite()

    XCTAssertEqual(model.currentAsset?.isFavorite, false)
    XCTAssertNotNil(model.favoriteErrorMessage)
}
```

```swift
@MainActor
final class AlbumPickerViewModelTests: XCTestCase {
    func testLoadPopulatesAlbumsAndMembership() async throws {
        let library = MockPhotoLibraryService.sample
        await library.setAlbumMembership(["asset-1"], for: "album")
        let model = AlbumPickerViewModel(assetID: "asset-1", library: library)

        await model.load()

        XCTAssertEqual(model.filteredAlbums.map(\.id), ["album"])
        XCTAssertTrue(model.isMember(of: model.filteredAlbums[0]))
    }

    func testSearchFiltersByTitle() async throws { /* seed two albums, assert filteredAlbums narrows */ }

    func testAddIsOptimisticAndPersists() async throws { /* add(to:), assert isMember true + albumAssignments recorded */ }

    func testFailedAddRollsBackMembership() async throws { /* forced failure, assert isMember reverts + errorMessage set */ }

    func testCreateAlbumInsertsAndAutoAdds() async throws { /* createAlbum(named:), assert new album in filteredAlbums and isMember true */ }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/CleanerViewModelTests -only-testing:PhotoCleanerTests/AlbumPickerViewModelTests test`

Expected: compilation fails — `toggleFavorite()`, `favoriteErrorMessage`,
and `AlbumPickerViewModel` do not exist.

- [ ] **Step 3: Implement `CleanerViewModel.toggleFavorite()`**

Add `private(set) var favoriteErrorMessage: String?` and:

```swift
func toggleFavorite() async {
    guard let assetID = currentAsset?.id,
          let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
    let newValue = !assets[index].isFavorite
    assets[index].isFavorite = newValue
    favoriteErrorMessage = nil
    do {
        try await library.setFavorite(newValue, assetID: assetID)
    } catch {
        assets[index].isFavorite = !newValue
        favoriteErrorMessage = "This photo's favorite status could not be updated. Please try again."
    }
}

func clearFavoriteError() { favoriteErrorMessage = nil }

func makeAlbumPickerViewModel(assetID: String) -> AlbumPickerViewModel {
    AlbumPickerViewModel(assetID: assetID, library: library)
}
```

- [ ] **Step 4: Implement `AlbumPickerViewModel`**

```swift
@MainActor
@Observable
final class AlbumPickerViewModel {
    enum State: Equatable {
        case loading
        case content(albums: [PhotoAlbum])
        case empty
        case failed(message: String)
    }

    private let assetID: String
    private let library: any PhotoLibraryServiceProtocol

    private(set) var state: State = .loading
    private(set) var membershipAlbumIDs: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var isCreatingAlbum = false
    private(set) var createAlbumErrorMessage: String?
    var searchText = ""

    init(assetID: String, library: any PhotoLibraryServiceProtocol) {
        self.assetID = assetID
        self.library = library
    }

    var filteredAlbums: [PhotoAlbum] {
        guard case let .content(albums) = state else { return [] }
        guard !searchText.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func isMember(of album: PhotoAlbum) -> Bool { membershipAlbumIDs.contains(album.id) }

    func load() async {
        state = .loading
        do {
            async let albums = library.fetchAlbums()
            async let membership = library.albumIDs(containingAssetID: assetID)
            let (fetchedAlbums, fetchedMembership) = try await (albums, membership)
            membershipAlbumIDs = fetchedMembership
            state = fetchedAlbums.isEmpty ? .empty : .content(albums: fetchedAlbums)
        } catch {
            state = .failed(message: "Albums could not be loaded. Please try again.")
        }
    }

    func add(to album: PhotoAlbum) async {
        guard !isMember(of: album) else { return }
        membershipAlbumIDs.insert(album.id)
        errorMessage = nil
        do {
            try await library.addAsset(assetID, toAlbum: album.id)
        } catch {
            membershipAlbumIDs.remove(album.id)
            errorMessage = "Could not add this photo to \"\(album.title)\". Please try again."
        }
    }

    func createAlbum(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isCreatingAlbum = true
        createAlbumErrorMessage = nil
        defer { isCreatingAlbum = false }
        do {
            let album = try await library.createAlbum(named: trimmed)
            var albums = (state.asAlbums ?? [])
            albums.append(album)
            albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            state = .content(albums: albums)
            await add(to: album)
        } catch {
            createAlbumErrorMessage = "This album could not be created. Please try again."
        }
    }

    func dismissError() { errorMessage = nil }
    func dismissCreateAlbumError() { createAlbumErrorMessage = nil }
}

private extension AlbumPickerViewModel.State {
    var asAlbums: [PhotoAlbum]? {
        if case let .content(albums) = self { albums } else { nil }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run the Step 2 command again. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Wire the UI**

`CleanerView`: turn the favorite `Label` into a `Button { Task { await
model.toggleFavorite() } }`, add an alert bound to
`model.favoriteErrorMessage` (mirrors the existing save-error alert).
Replace the disabled "Album Unavailable" button with an enabled
`Button("Add to Album", systemImage: "rectangle.stack.badge.plus")` that
sets `@State private var isPresentingAlbumPicker = true`, disabled when
`model.currentAsset == nil`. Add:

```swift
.sheet(isPresented: $isPresentingAlbumPicker) {
    if let assetID = model.currentAsset?.id {
        NavigationStack {
            AlbumPickerView(model: model.makeAlbumPickerViewModel(assetID: assetID))
        }
    }
}
```

`AlbumPickerView`: a `List` over `model.filteredAlbums` with
`.searchable(text: $model.searchText)`, each row showing title, photo
count, and a checkmark when `model.isMember(of:)`, tapping calls
`Task { await model.add(to: album) }`. Toolbar: a "New Album" button
presenting a `.alert` with a `TextField` calling
`model.createAlbum(named:)`, and a "Done" button dismissing the sheet.
Loading/empty/failed states mirror `SourcePickerView`'s `content`
switch.

- [ ] **Step 7: Run full suite and static safety checks**

Run: `rg -n 'deleteAssets' PhotoCleaner/Features PhotoCleaner/App`

Expected: only `DeletionReviewViewModel.confirmDeletion()`.

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build`

Run: `xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test`

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`, every prior
test still passing alongside the new ones.

- [ ] **Step 8: Update status and commit**

Update `docs/STATUS.md`: Milestone 4 → complete, with a verification
entry (exact build/test results, new test count).

```bash
git add PhotoCleaner/Features/Cleaner PhotoCleaner/Features/AlbumPicker PhotoCleanerTests/CleanerViewModelTests.swift PhotoCleanerTests/AlbumPickerViewModelTests.swift docs/STATUS.md
git commit -m "feat: add favorite toggle and album picker"
```

## Remaining manual checks

Real favorite toggle against a seeded simulator library, the album
picker's search and existing-membership checkmarks against real album
contents, album creation, and VoiceOver/Dynamic Type on the new sheet —
all require interactive simulator/device use.
