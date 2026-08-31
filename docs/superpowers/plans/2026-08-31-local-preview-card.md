# Local Preview Photo Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a printed-photo Cleaner card that shows locally available mock previews, `dd/MM/yy` capture dates, raw coordinates, approved fallbacks, and accessible metadata without networking or persisted image bytes.

**Architecture:** Framework-independent domain values describe coordinates and transient preview content. `PhotoLibraryServiceProtocol` exposes a local-only preview request, its actor-backed mock records deterministic requests, and the main-actor Cleaner view model protects the current card from stale asynchronous results. SwiftUI renders a focused printed-card component while cleaning decisions remain independent of preview availability.

**Tech Stack:** Swift 6, SwiftUI, Foundation, Observation, XCTest, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-31-local-preview-card-design.md`

## Global Constraints

- Do not import PhotoKit, CoreLocation, or SwiftData in this foundation change.
- Do not request network access, reverse geocode coordinates, or persist preview bytes.
- Location uses raw latitude/longitude formatted to four decimal places.
- Missing metadata uses exactly `Unknown date` and `No location`.
- Capture dates use exactly `dd/MM/yy` with a Gregorian calendar and UTC for deterministic tests.
- Keep, queue-for-deletion, undo, save, and preview loading must never call `deleteAssets(ids:)`.
- All observable UI state remains on the main actor.
- Run every build and test against `platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini`.

---

### Task 1: Photo metadata and presentation labels

**Files:**
- Modify: `PhotoCleaner/Domain/Models/PhotoAsset.swift`
- Create: `PhotoCleaner/Features/Cleaner/PhotoCardMetadata.swift`
- Modify: `PhotoCleaner/Services/MockPhotoLibraryService.swift`
- Create: `PhotoCleanerTests/PhotoCardMetadataTests.swift`

**Interfaces:**
- Consumes: `PhotoAsset.id`, `creationDate`, `isFavorite`, and `previewSymbolName`.
- Produces: optional `PhotoAsset.latitude`, optional `PhotoAsset.longitude`, `PhotoCardMetadata.init(asset:)`, `dateText`, `locationText`, and `accessibilityValue`.

- [ ] **Step 1: Write failing metadata tests**

```swift
import Foundation
import XCTest
@testable import PhotoCleaner

@MainActor
final class PhotoCardMetadataTests: XCTestCase {
    func testFormatsDateAndCoordinatesWithoutGeocoding() {
        let asset = PhotoAsset(
            id: "a",
            creationDate: Date(timeIntervalSince1970: 1_704_067_200),
            isFavorite: false,
            previewSymbolName: "photo",
            latitude: 37.5665,
            longitude: 126.9780
        )

        let metadata = PhotoCardMetadata(asset: asset)

        XCTAssertEqual(metadata.dateText, "01/01/24")
        XCTAssertEqual(metadata.locationText, "37.5665, 126.9780")
        XCTAssertEqual(
            metadata.accessibilityValue,
            "Captured 01/01/24. Location 37.5665, 126.9780."
        )
    }

    func testUsesApprovedFallbacksForMissingMetadata() {
        let asset = PhotoAsset(
            id: "a",
            creationDate: nil,
            isFavorite: false,
            previewSymbolName: "photo",
            latitude: nil,
            longitude: nil
        )

        let metadata = PhotoCardMetadata(asset: asset)

        XCTAssertEqual(metadata.dateText, "Unknown date")
        XCTAssertEqual(metadata.locationText, "No location")
        XCTAssertEqual(
            metadata.accessibilityValue,
            "Captured Unknown date. Location No location."
        )
    }
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/PhotoCardMetadataTests test
```

Expected: compilation fails because the coordinate initializer parameters and `PhotoCardMetadata` do not exist.

- [ ] **Step 3: Extend `PhotoAsset` without breaking existing callers**

```swift
struct PhotoAsset: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let creationDate: Date?
    var isFavorite: Bool
    let previewSymbolName: String
    let latitude: Double?
    let longitude: Double?

    init(
        id: String,
        creationDate: Date?,
        isFavorite: Bool,
        previewSymbolName: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.isFavorite = isFavorite
        self.previewSymbolName = previewSymbolName
        self.latitude = latitude
        self.longitude = longitude
    }
}
```

Update the three sample assets with deterministic coordinate pairs; leave one asset without coordinates to exercise fallback UI manually.

- [ ] **Step 4: Implement deterministic presentation labels**

```swift
import Foundation

struct PhotoCardMetadata: Equatable, Sendable {
    let dateText: String
    let locationText: String

    init(asset: PhotoAsset) {
        if let creationDate = asset.creationDate {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "dd/MM/yy"
            dateText = formatter.string(from: creationDate)
        } else {
            dateText = "Unknown date"
        }

        if let latitude = asset.latitude, let longitude = asset.longitude {
            locationText = String(
                format: "%.4f, %.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude,
                longitude
            )
        } else {
            locationText = "No location"
        }
    }

    var accessibilityValue: String {
        "Captured \(dateText). Location \(locationText)."
    }
}
```

- [ ] **Step 5: Run focused and existing domain tests**

Run the Step 2 command, then:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/CleaningSessionTests -only-testing:PhotoCleanerTests/MockServicesTests test
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

```sh
git add PhotoCleaner/Domain/Models/PhotoAsset.swift PhotoCleaner/Features/Cleaner/PhotoCardMetadata.swift PhotoCleaner/Services/MockPhotoLibraryService.swift PhotoCleanerTests/PhotoCardMetadataTests.swift
git commit -m "feat: add cleaner card metadata"
```

### Task 2: Local-only preview contract and deterministic mock

**Files:**
- Create: `PhotoCleaner/Domain/Models/LocalPhotoPreview.swift`
- Modify: `PhotoCleaner/Domain/Protocols/PhotoLibraryServiceProtocol.swift`
- Modify: `PhotoCleaner/Services/MockPhotoLibraryService.swift`
- Create: `PhotoCleanerTests/LocalPhotoPreviewTests.swift`

**Interfaces:**
- Consumes: asset identifiers and target pixel dimensions.
- Produces: `PhotoPreviewRequest`, `LocalPhotoPreviewContent`, `LocalPhotoPreview`, `PhotoLibraryServiceProtocol.fetchLocalPreview(for:)`, mock `previewRequests`, `setPreview(_:for:)`, and `setPreviewDelayNanoseconds(_:for:)`.

- [ ] **Step 1: Write failing request and mock tests**

```swift
import XCTest
@testable import PhotoCleaner

final class LocalPhotoPreviewTests: XCTestCase {
    func testRequestClampsPixelDimensionsAndMockRecordsLocalOnlyRequest() async throws {
        let service = MockPhotoLibraryService.sample
        let request = PhotoPreviewRequest(assetID: "asset-1", pixelWidth: 0, pixelHeight: -4)

        let preview = try await service.fetchLocalPreview(for: request)
        let recorded = await service.previewRequests

        XCTAssertEqual(request.pixelWidth, 1)
        XCTAssertEqual(request.pixelHeight, 1)
        XCTAssertEqual(recorded, [request])
        XCTAssertEqual(preview?.content, .systemSymbol("photo"))
    }

    func testUnavailableLocalPreviewReturnsNilWithoutDeletion() async throws {
        let service = MockPhotoLibraryService()
        let request = PhotoPreviewRequest(assetID: "missing", pixelWidth: 600, pixelHeight: 600)

        let preview = try await service.fetchLocalPreview(for: request)
        let deletedBatches = await service.deletedIDBatches

        XCTAssertNil(preview)
        XCTAssertTrue(deletedBatches.isEmpty)
    }
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/LocalPhotoPreviewTests test
```

Expected: compilation fails because the preview types and service method do not exist.

- [ ] **Step 3: Add framework-independent preview values**

```swift
import Foundation

struct PhotoPreviewRequest: Hashable, Codable, Sendable {
    let assetID: String
    let pixelWidth: Int
    let pixelHeight: Int

    init(assetID: String, pixelWidth: Int, pixelHeight: Int) {
        self.assetID = assetID
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
    }
}

enum LocalPhotoPreviewContent: Equatable, Sendable {
    case systemSymbol(String)
    case encodedImageData(Data)
}

struct LocalPhotoPreview: Equatable, Sendable {
    let content: LocalPhotoPreviewContent
    let isDegraded: Bool
}
```

- [ ] **Step 4: Extend the service boundary**

Add this exact requirement to `PhotoLibraryServiceProtocol`:

```swift
func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview?
```

The method name and lack of a network flag make local-only behavior mandatory rather than caller-configurable.

- [ ] **Step 5: Implement mock previews, request recording, and configurable delay**

Add actor-isolated storage:

```swift
private var previewsByAssetID: [String: LocalPhotoPreview]
private var previewDelayNanosecondsByAssetID: [String: UInt64] = [:]
private(set) var previewRequests: [PhotoPreviewRequest] = []
```

Accept `previewsByAssetID` in the mock initializer with a default empty dictionary. Configure `.sample` with symbol previews matching its three assets. Implement:

```swift
func setPreview(_ preview: LocalPhotoPreview?, for assetID: String) {
    previewsByAssetID[assetID] = preview
}

func setPreviewDelayNanoseconds(_ delay: UInt64, for assetID: String) {
    previewDelayNanosecondsByAssetID[assetID] = delay
}

func fetchLocalPreview(for request: PhotoPreviewRequest) async throws -> LocalPhotoPreview? {
    try throwIfForced()
    previewRequests.append(request)
    let delay = previewDelayNanosecondsByAssetID[request.assetID] ?? 0
    let preview = previewsByAssetID[request.assetID]
    if delay > 0 {
        try await Task.sleep(nanoseconds: delay)
    }
    return preview
}
```

- [ ] **Step 6: Run focused tests and the mock safety suite**

Run the Step 2 command, then:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/MockServicesTests -only-testing:PhotoCleanerTests/SafetyInvariantTests test
```

Expected: all selected tests pass and deletion recordings remain empty outside the explicit mock deletion test.

- [ ] **Step 7: Commit**

```sh
git add PhotoCleaner/Domain/Models/LocalPhotoPreview.swift PhotoCleaner/Domain/Protocols/PhotoLibraryServiceProtocol.swift PhotoCleaner/Services/MockPhotoLibraryService.swift PhotoCleanerTests/LocalPhotoPreviewTests.swift
git commit -m "feat: add local-only preview boundary"
```

### Task 3: Stale-safe Cleaner preview loading and printed card

**Files:**
- Modify: `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift`
- Create: `PhotoCleaner/Features/Cleaner/PrintedPhotoCard.swift`
- Modify: `PhotoCleaner/Features/Cleaner/CleanerView.swift`
- Modify: `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift`
- Modify: `PhotoCleanerTests/CleanerViewModelTests.swift`
- Modify: `PhotoCleanerTests/SafetyInvariantTests.swift`

**Interfaces:**
- Consumes: `PhotoCardMetadata`, `PhotoPreviewRequest`, `LocalPhotoPreview`, and existing cleaning-session actions.
- Produces: `CleanerViewModel.currentPreview`, `previewStatusText`, `loadCurrentPreview(pixelWidth:pixelHeight:)`, and `PrintedPhotoCard`.

- [ ] **Step 1: Write failing Cleaner preview tests**

Add to `CleanerViewModelTests`:

```swift
func testUnavailablePreviewDoesNotBlockQueueDecision() async {
    let library = MockPhotoLibraryService(
        albums: [.init(id: "album", title: "Mock Album", photoCount: 1)],
        assetsBySource: [
            .album(.init(id: "album", title: "Mock Album", photoCount: 1)): [
                .init(id: "a", creationDate: nil, isFavorite: false, previewSymbolName: "photo")
            ]
        ]
    )
    let repository = InMemorySessionRepository()
    let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 1))
    let model = CleanerViewModel(source: source, library: library, sessions: repository)

    await model.load()
    await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
    await model.queueCurrentForDeletion()

    XCTAssertNil(model.currentPreview)
    XCTAssertEqual(model.previewStatusText, "Local preview unavailable")
    XCTAssertEqual(model.session.pendingDeletionIDs, ["a"])
}

func testLatePreviewCannotReplaceNewCurrentAssetPreview() async throws {
    let library = MockPhotoLibraryService.sample
    await library.setPreviewDelayNanoseconds(200_000_000, for: "asset-1")
    let repository = InMemorySessionRepository()
    let source = CleaningSource.album(.init(id: "album", title: "Mock Album", photoCount: 3))
    let model = CleanerViewModel(source: source, library: library, sessions: repository)

    await model.load()
    let firstRequest = Task {
        await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
    }
    try await Task.sleep(nanoseconds: 20_000_000)
    await model.keepCurrent()
    await model.loadCurrentPreview(pixelWidth: 600, pixelHeight: 600)
    await firstRequest.value

    XCTAssertEqual(model.currentAsset?.id, "asset-2")
    XCTAssertEqual(model.currentPreview?.content, .systemSymbol("photo.fill"))
}
```

Extend `SafetyInvariantTests` to call `loadCurrentPreview(pixelWidth:pixelHeight:)` before and after a decision, then retain the existing assertion that `deletedIDBatches` is empty.

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' -only-testing:PhotoCleanerTests/CleanerViewModelTests -only-testing:PhotoCleanerTests/SafetyInvariantTests test
```

Expected: compilation fails because Cleaner preview state and loading do not exist.

- [ ] **Step 3: Implement stale-safe main-actor preview state**

Add to `CleanerViewModel`:

```swift
private var previewGeneration = 0
private(set) var currentPreview: LocalPhotoPreview?
private(set) var previewStatusText: String?

func loadCurrentPreview(pixelWidth: Int, pixelHeight: Int) async {
    previewGeneration += 1
    let generation = previewGeneration
    guard let assetID = currentAsset?.id else {
        currentPreview = nil
        previewStatusText = nil
        return
    }

    do {
        let request = PhotoPreviewRequest(
            assetID: assetID,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        let preview = try await library.fetchLocalPreview(for: request)
        guard generation == previewGeneration, currentAsset?.id == assetID else { return }
        currentPreview = preview
        previewStatusText = preview == nil ? "Local preview unavailable" : nil
    } catch is CancellationError {
        return
    } catch {
        guard generation == previewGeneration, currentAsset?.id == assetID else { return }
        currentPreview = nil
        previewStatusText = "Local preview unavailable"
    }
}
```

Increment `previewGeneration`, clear `currentPreview`, and clear the status whenever a decision, undo, or load changes the current asset. Preview errors must not assign `errorMessage`, because that state currently replaces the whole Cleaner UI and would block decisions.

- [ ] **Step 4: Create the printed-photo card component**

Implement `PrintedPhotoCard` with this interface:

```swift
struct PrintedPhotoCard: View {
    let preview: LocalPhotoPreview?
    let metadata: PhotoCardMetadata
    let previewStatusText: String?
    let isFavorite: Bool
    let keepAction: () -> Void
    let queueAction: () -> Void
}
```

Render a white `VStack` frame with `PhotoCleanerTheme.photoFrameInset` around an aspect-fit preview area and `PhotoCleanerTheme.photoFrameBottomInset` below it. Display `.systemSymbol` with `Image(systemName:)`; decode `.encodedImageData` with `UIImage(data:)`; use `Image(systemName: "photo")` when unavailable or undecodable. Put `metadata.dateText` leading and `metadata.locationText` trailing in the bottom margin with multiline text and `minimumScaleFactor(0.8)`. Apply:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("Photo for review")
.accessibilityValue("\(metadata.accessibilityValue) \(isFavorite ? "Favorite." : "Not favorite.")")
.accessibilityAction(named: "Keep Photo", keepAction)
.accessibilityAction(named: "Queue for Deletion", queueAction)
```

Show `previewStatusText` as visible secondary text inside the preview area so preview availability is not conveyed only by the placeholder graphic.

- [ ] **Step 5: Integrate the card without changing decision controls**

Replace the existing preview image/date/favorite block in `CleanerView` with `PrintedPhotoCard`. Preserve the existing drag gesture on the card, visible Keep and Queue buttons, Undo, disabled Album control, and Close & Save. Use a `.task(id: model.currentAsset?.id)` to request a `900 x 900` local preview:

```swift
.task(id: model.currentAsset?.id) {
    await model.loadCurrentPreview(pixelWidth: 900, pixelHeight: 900)
}
```

Add exact theme constants:

```swift
static let photoFrameInset: CGFloat = 12
static let photoFrameBottomInset: CGFloat = 24
```

- [ ] **Step 6: Run focused tests**

Run the Step 2 command and the Task 1 metadata test command.

Expected: all Cleaner, safety, and metadata tests pass.

- [ ] **Step 7: Run static safety checks**

Run:

```sh
rg -n '^import (PhotoKit|CoreLocation|SwiftData)' PhotoCleaner PhotoCleanerTests
```

Expected: no output and exit status 1.

Run:

```sh
rg -n 'deleteAssets' PhotoCleaner/Features PhotoCleaner/App
```

Expected: no output and exit status 1.

Run:

```sh
git diff --check
```

Expected: no output and exit status 0.

- [ ] **Step 8: Run the complete build and test suite**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, and all tests pass. The project has no UI-test target, so report automated UI tests as unavailable rather than claiming they passed.

- [ ] **Step 9: Commit**

```sh
git add PhotoCleaner/Features/Cleaner PhotoCleaner/DesignSystem PhotoCleanerTests/CleanerViewModelTests.swift PhotoCleanerTests/SafetyInvariantTests.swift
git commit -m "feat: add printed local preview card"
```

## Remaining manual checks

On `PhotoCleaner iPhone 13 mini`, launch the app and verify the printed frame at standard and largest accessibility Dynamic Type sizes; date and coordinates wrap without clipping; `Unknown date` and `No location` are visible; VoiceOver announces date, location, favorite state, Keep, and Queue; unavailable previews retain functional swipe/buttons; rapid decisions never flash the previous asset preview; portrait layout remains usable; no photo permission or network prompt appears.
