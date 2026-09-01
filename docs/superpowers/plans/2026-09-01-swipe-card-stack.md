# Swipe Card Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a responsive, accessible three-card swipe stack that displays the first local preview result immediately and records safe keep or pending-delete decisions through one commit path.

**Architecture:** Pure gesture math and a small commit gate make threshold, rotation, stamps, and duplicate prevention independently testable. `CleanerViewModel` owns a first-result preview cache for the visible three-asset window, while `SwipeCardStack` owns transient SwiftUI animation and haptic state and delegates decisions back to the view model.

**Tech Stack:** Swift 6, SwiftUI, Observation, structured concurrency, XCTest, Xcode 26.6, iOS 17+

**Spec:** `docs/superpowers/specs/2026-09-01-swipe-card-stack-design.md`

## Global Constraints

- Target iPhone only, with the iPhone 13 mini as the primary build, test, and layout destination.
- A left swipe adds only a pending-delete session decision; it never calls permanent deletion.
- Gesture, visible buttons, and named accessibility actions use the same commit behavior.
- Display the first local preview result, even when degraded; never replace it with a later higher-quality result.
- Do not add PhotoKit, SwiftData, persisted image bytes, network access, third-party dependencies, or unrelated feature changes.
- Keep UI state changes on the main actor and services injectable through existing protocols.
- Reduced Motion uses a cross-fade; normal motion uses fly-off and spring animations.

---

## File map

- Create `PhotoCleaner/Features/Cleaner/SwipeCardInteraction.swift`: pure swipe direction, transform, stamp, and duplicate-commit rules.
- Create `PhotoCleanerTests/SwipeCardInteractionTests.swift`: boundary and mutation-catching tests for those rules.
- Modify `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift`: visible three-asset window and frozen first-result preview cache.
- Modify `PhotoCleanerTests/CleanerViewModelTests.swift`: visible-window, concurrent load, unavailable, and first-result tests.
- Modify `PhotoCleaner/Features/Cleaner/PrintedPhotoCard.swift`: optional bordered text stamp and interactive/noninteractive accessibility behavior.
- Create `PhotoCleaner/Features/Cleaner/SwipeCardStack.swift`: card layering, drag, animations, unified commit, Reduced Motion, and haptic trigger.
- Modify `PhotoCleaner/Features/Cleaner/CleanerView.swift`: replace the fixed card gesture with the stack and visible shared actions.
- Modify `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift`: approved interaction/layout constants.
- Modify `PhotoCleanerTests/SafetyInvariantTests.swift`: exercise stack-equivalent keep and queue sequencing without calling deletion.
- Modify `docs/STATUS.md`: record delivered behavior, verification, and remaining manual checks.

---

### Task 1: Pure swipe interaction rules

**Files:**
- Create: `PhotoCleanerTests/SwipeCardInteractionTests.swift`
- Create: `PhotoCleaner/Features/Cleaner/SwipeCardInteraction.swift`

**Interfaces:**
- Produces: `SwipeCommitDirection`, `SwipeStamp`, `SwipeCardInteraction`, and `SwipeCommitGate` for `SwipeCardStack`.
- Consumes: no application service or session state.

- [ ] **Step 1: Write failing threshold and transform tests**

Name the breaks first: these tests must fail if the threshold becomes fixed-width, if equality does not commit, if rotation exceeds 8 degrees, or if a neutral drag displays a stamp.

```swift
import XCTest
@testable import PhotoCleaner

final class SwipeCardInteractionTests: XCTestCase {
    func testCommitRequiresOneQuarterOfMeasuredWidthAndIncludesBoundary() {
        XCTAssertNil(SwipeCardInteraction.commitDirection(translation: 79, cardWidth: 320))
        XCTAssertEqual(SwipeCardInteraction.commitDirection(translation: 80, cardWidth: 320), .keep)
        XCTAssertEqual(SwipeCardInteraction.commitDirection(translation: -80, cardWidth: 320), .delete)
    }

    func testRotationIsProportionalAndCappedInBothDirections() {
        XCTAssertEqual(SwipeCardInteraction.rotationDegrees(translation: 80, cardWidth: 320), 2, accuracy: 0.001)
        XCTAssertEqual(SwipeCardInteraction.rotationDegrees(translation: 640, cardWidth: 320), 8, accuracy: 0.001)
        XCTAssertEqual(SwipeCardInteraction.rotationDegrees(translation: -640, cardWidth: 320), -8, accuracy: 0.001)
    }

    func testStampUsesDirectionTextAndDistanceOpacity() {
        XCTAssertNil(SwipeCardInteraction.stamp(translation: 0, cardWidth: 320))
        XCTAssertEqual(SwipeCardInteraction.stamp(translation: 40, cardWidth: 320), .init(direction: .keep, opacity: 0.5))
        XCTAssertEqual(SwipeCardInteraction.stamp(translation: -80, cardWidth: 320), .init(direction: .delete, opacity: 1))
    }

    func testInvalidCardWidthCannotCommitOrRotate() {
        XCTAssertNil(SwipeCardInteraction.commitDirection(translation: 100, cardWidth: 0))
        XCTAssertEqual(SwipeCardInteraction.rotationDegrees(translation: 100, cardWidth: 0), 0)
    }
}
```

- [ ] **Step 2: Run the new test file and verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/SwipeCardInteractionTests test
```

Expected: compilation fails because `SwipeCardInteraction` and related types do not exist.

- [ ] **Step 3: Implement the minimal pure interaction types**

Create `SwipeCardInteraction.swift` with these exact public-to-module interfaces:

```swift
import CoreGraphics

enum SwipeCommitDirection: Equatable, Sendable {
    case keep
    case delete

    var sign: CGFloat { self == .keep ? 1 : -1 }
}

struct SwipeStamp: Equatable, Sendable {
    let direction: SwipeCommitDirection
    let opacity: Double
}

enum SwipeCardInteraction {
    static let commitFraction: CGFloat = 0.25
    static let maximumRotationDegrees: Double = 8

    static func commitDirection(translation: CGFloat, cardWidth: CGFloat) -> SwipeCommitDirection? {
        guard cardWidth > 0 else { return nil }
        let threshold = cardWidth * commitFraction
        if translation >= threshold { return .keep }
        if translation <= -threshold { return .delete }
        return nil
    }

    static func rotationDegrees(translation: CGFloat, cardWidth: CGFloat) -> Double {
        guard cardWidth > 0 else { return 0 }
        let proportional = Double(translation / cardWidth) * maximumRotationDegrees
        return min(max(proportional, -maximumRotationDegrees), maximumRotationDegrees)
    }

    static func stamp(translation: CGFloat, cardWidth: CGFloat) -> SwipeStamp? {
        guard cardWidth > 0, translation != 0 else { return nil }
        let opacity = min(abs(translation) / (cardWidth * commitFraction), 1)
        return SwipeStamp(
            direction: translation > 0 ? .keep : .delete,
            opacity: Double(opacity)
        )
    }
}
```

- [ ] **Step 4: Run the interaction tests and verify GREEN**

Run the command from Step 2. Expected: `SwipeCardInteractionTests` passes.

- [ ] **Step 5: Add a failing duplicate-commit gate test**

Name the break: this test fails if rapid gesture/button/accessibility inputs can begin a second commit before the first transition finishes.

```swift
func testCommitGateAcceptsOnlyOneCommitUntilReset() {
    var gate = SwipeCommitGate()

    XCTAssertTrue(gate.begin())
    XCTAssertFalse(gate.begin())
    gate.reset()
    XCTAssertTrue(gate.begin())
}
```

Run the Step 2 command. Expected: compilation fails because `SwipeCommitGate` does not exist.

- [ ] **Step 6: Implement the minimal commit gate and verify GREEN**

Append:

```swift
struct SwipeCommitGate: Equatable, Sendable {
    private(set) var isCommitting = false

    mutating func begin() -> Bool {
        guard !isCommitting else { return false }
        isCommitting = true
        return true
    }

    mutating func reset() {
        isCommitting = false
    }
}
```

Run the Step 2 command. Expected: all interaction tests pass.

- [ ] **Step 7: Commit Task 1**

```sh
git add PhotoCleaner/Features/Cleaner/SwipeCardInteraction.swift \
  PhotoCleanerTests/SwipeCardInteractionTests.swift
git commit -m "feat: define swipe card interaction rules"
```

---

### Task 2: Visible card window and first-result preview cache

**Files:**
- Modify: `PhotoCleanerTests/CleanerViewModelTests.swift`
- Modify: `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift`

**Interfaces:**
- Produces: `CleanerCardItem`, `visibleCards`, and `loadVisiblePreviews(pixelWidth:pixelHeight:)`.
- Preserves: `currentAsset`, `currentPreview`, `previewStatusText`, and `loadCurrentPreview(pixelWidth:pixelHeight:)` for existing callers/tests.
- Consumes: `PhotoLibraryServiceProtocol.fetchLocalPreview(for:)`; no PhotoKit types.

- [ ] **Step 1: Write failing visible-window test**

Name the break: this fails if the view model exposes more than three cards, returns the wrong order, or fails to advance the window after a decision.

```swift
func testVisibleCardsContainCurrentAndAtMostTwoSuccessorsInOrder() async {
    let library = MockPhotoLibraryService.sample
    let model = CleanerViewModel(
        source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
        library: library,
        sessions: InMemorySessionRepository()
    )

    await model.load()
    XCTAssertEqual(model.visibleCards.map(\.id), ["asset-1", "asset-2", "asset-3"])

    await model.keepCurrent()
    XCTAssertEqual(model.visibleCards.map(\.id), ["asset-2", "asset-3"])
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/CleanerViewModelTests/testVisibleCardsContainCurrentAndAtMostTwoSuccessorsInOrder test
```

Expected: compilation fails because `visibleCards` does not exist.

- [ ] **Step 3: Add the minimal card item and visible window**

Add above `CleanerViewModel`:

```swift
struct CleanerCardItem: Identifiable, Equatable, Sendable {
    let asset: PhotoAsset
    let preview: LocalPhotoPreview?
    let previewStatusText: String?

    var id: String { asset.id }
}

private enum CachedPreview: Equatable, Sendable {
    case loading
    case available(LocalPhotoPreview)
    case unavailable
}
```

Replace scalar preview storage with `private var previewsByAssetID: [String: CachedPreview] = [:]`, and derive:

```swift
var visibleCards: [CleanerCardItem] {
    let availableByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
    return session.orderedAssetIDs
        .dropFirst(session.currentPosition)
        .prefix(3)
        .compactMap { id in
            guard let asset = availableByID[id] else { return nil }
            return CleanerCardItem(
                asset: asset,
                preview: preview(for: id),
                previewStatusText: previewStatus(for: id)
            )
        }
}
```

Use private helpers that map `.available` to its preview, `.unavailable` to
`"Local preview unavailable"`, and `.loading`/missing to `nil` without a status.
Keep `currentPreview` and `previewStatusText` as computed properties for the
first visible card so existing behavior remains source-compatible.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the command from Step 2. Expected: the visible-window test passes.

- [ ] **Step 5: Write failing concurrent-load and frozen-result tests**

Name the breaks: these fail if the rear cards are not requested, if degraded
previews are rejected, or if a later request replaces the first displayed
result.

```swift
func testLoadVisiblePreviewsRequestsAllThreeCardsAndAcceptsDegradedResult() async {
    let library = MockPhotoLibraryService.sample
    await library.setPreview(
        .init(content: .systemSymbol("first-quality"), isDegraded: true),
        for: "asset-1"
    )
    let model = CleanerViewModel(
        source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
        library: library,
        sessions: InMemorySessionRepository()
    )

    await model.load()
    await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)

    XCTAssertEqual(Set((await library.previewRequests).map(\.assetID)), Set(["asset-1", "asset-2", "asset-3"]))
    XCTAssertEqual(model.visibleCards.first?.preview?.content, .systemSymbol("first-quality"))
    XCTAssertEqual(model.visibleCards.first?.preview?.isDegraded, true)
}

func testFirstCompletedPreviewIsFrozenForAsset() async {
    let library = MockPhotoLibraryService.sample
    await library.setPreview(
        .init(content: .systemSymbol("first-quality"), isDegraded: true),
        for: "asset-1"
    )
    let model = CleanerViewModel(
        source: .album(.init(id: "album", title: "Mock Album", photoCount: 3)),
        library: library,
        sessions: InMemorySessionRepository()
    )

    await model.load()
    await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)
    await library.setPreview(
        .init(content: .systemSymbol("later-quality"), isDegraded: false),
        for: "asset-1"
    )
    await model.loadVisiblePreviews(pixelWidth: 1200, pixelHeight: 1200)

    XCTAssertEqual(model.visibleCards.first?.preview?.content, .systemSymbol("first-quality"))
    XCTAssertEqual((await library.previewRequests).filter { $0.assetID == "asset-1" }.count, 1)
}
```

- [ ] **Step 6: Run the two new tests and verify RED**

Run both via:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/CleanerViewModelTests test
```

Expected: compilation fails because `loadVisiblePreviews` does not exist.

- [ ] **Step 7: Implement concurrent visible preview loading**

Implement `loadVisiblePreviews` so it:

1. Captures IDs from `visibleCards` whose cache entry is absent.
2. Marks those IDs `.loading` on the main actor before requests begin.
3. Uses `withTaskGroup` to call the injected Sendable service concurrently.
4. Stores the first returned preview as `.available`, `nil`/non-cancellation
   failure as `.unavailable`, and removes `.loading` on cancellation so a later
   appearance may retry.
5. Writes only when the entry is still `.loading`; an already finalized value
   is never replaced.

Retain `loadCurrentPreview` as a wrapper around the same per-ID cache loading
path, not a second implementation. Remove the old generation/scalar preview
logic only after the existing stale-preview test passes against the new cache.

- [ ] **Step 8: Run all Cleaner view-model tests and verify GREEN**

Run the command from Step 6. Expected: all `CleanerViewModelTests` pass,
including existing late-result, unavailable, decision, undo, and save tests.

- [ ] **Step 9: Commit Task 2**

```sh
git add PhotoCleaner/Features/Cleaner/CleanerViewModel.swift \
  PhotoCleanerTests/CleanerViewModelTests.swift
git commit -m "feat: cache first previews for cleaner stack"
```

---

### Task 3: Printed-card stamps and accessible interactivity

**Files:**
- Modify: `PhotoCleanerTests/CleanerViewModelTests.swift`
- Modify: `PhotoCleaner/Features/Cleaner/PrintedPhotoCard.swift`
- Modify: `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift`

**Interfaces:**
- Produces: `PrintedPhotoCardStampPresentation` and optional `stamp` and `isInteractive` inputs on `PrintedPhotoCard`.
- Consumes: `SwipeStamp` and existing `PrintedPhotoCardPreviewPresentation`.

- [ ] **Step 1: Write failing stamp presentation tests**

Name the breaks: these fail if text is omitted, direction is reversed, opacity
is discarded, or state relies only on color.

```swift
func testKeepStampPresentationIncludesTextAndOpacity() {
    let presentation = PrintedPhotoCardStampPresentation(
        stamp: .init(direction: .keep, opacity: 0.5)
    )

    XCTAssertEqual(presentation?.text, "KEEP")
    XCTAssertEqual(presentation?.opacity, 0.5)
}

func testDeleteStampPresentationIncludesText() {
    let presentation = PrintedPhotoCardStampPresentation(
        stamp: .init(direction: .delete, opacity: 1)
    )

    XCTAssertEqual(presentation?.text, "DELETE")
    XCTAssertEqual(presentation?.opacity, 1)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/CleanerViewModelTests/testKeepStampPresentationIncludesTextAndOpacity \
  -only-testing:PhotoCleanerTests/CleanerViewModelTests/testDeleteStampPresentationIncludesText test
```

Expected: compilation fails because `PrintedPhotoCardStampPresentation` is missing.

- [ ] **Step 3: Add minimal stamp presentation and theme constants**

Add a presentation type that maps `.keep` to `KEEP`, `.delete` to `DELETE`,
retains opacity, and exposes direction for selecting `Color.green` or
`Color.red` in the view. Add theme constants for rear-card scale (`0.96` per
depth), vertical offset (`8` points per depth), stamp line width (`3`), normal
commit duration (`0.18` seconds), and reduced-motion duration (`0.12` seconds).

- [ ] **Step 4: Render the bordered text stamp**

Add `stamp: SwipeStamp? = nil` and `isInteractive: Bool = true` to
`PrintedPhotoCard`. Overlay the stamp near the leading top corner for keep and
trailing top corner for delete, with bold scalable text, a rounded bordered
shape, the presentation opacity, and an accessibility-hidden modifier because
the card's named action/state already communicates the decision. Apply named
Keep/Queue actions only to the interactive top card; mark rear instances hidden
from accessibility in `SwipeCardStack`.

- [ ] **Step 5: Run focused and existing card-presentation tests**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/CleanerViewModelTests test
```

Expected: all card preview/accessibility and stamp presentation tests pass.

- [ ] **Step 6: Commit Task 3**

```sh
git add PhotoCleaner/Features/Cleaner/PrintedPhotoCard.swift \
  PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift \
  PhotoCleanerTests/CleanerViewModelTests.swift
git commit -m "feat: add accessible swipe decision stamps"
```

---

### Task 4: Animated stack with unified gesture, button, and VoiceOver commits

**Files:**
- Create: `PhotoCleaner/Features/Cleaner/SwipeCardStack.swift`
- Modify: `PhotoCleaner/Features/Cleaner/CleanerView.swift`
- Modify: `PhotoCleanerTests/SafetyInvariantTests.swift`

**Interfaces:**
- Consumes: `[CleanerCardItem]`, `SwipeCardInteraction`, `SwipeCommitGate`, and `PrintedPhotoCard`.
- Produces: `SwipeCardStack(cards:keepAction:queueAction:)` with async decision closures.

- [ ] **Step 1: Strengthen the failing safety integration test before wiring UI**

Name the break: the test fails if a keep or delete-equivalent commit calls the
destructive service rather than only mutating the session.

Update the existing safety test to load the three-card window, perform a keep
then a queue decision through the exact view-model closures the stack will use,
and assert both session decisions plus an empty `deletedIDBatches` collection.
Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' \
  -only-testing:PhotoCleanerTests/SafetyInvariantTests test
```

Expected: the new visible-window/loading expectation fails until the integration
uses Task 2's API correctly; the deletion assertion must remain green.

- [ ] **Step 2: Create `SwipeCardStack` with layered rear cards**

Implement:

```swift
struct SwipeCardStack: View {
    let cards: [CleanerCardItem]
    let keepAction: () async -> Void
    let queueAction: () async -> Void
}
```

Use a `GeometryReader` and a `ZStack`. Render `cards.prefix(3)` in reverse order
so index zero is topmost. Rear cards use the per-depth scale/offset constants,
have no gesture, and are accessibility-hidden. Each uses its own frozen preview
and metadata.

- [ ] **Step 3: Add one commit path**

Keep `dragOffset`, `commitGate`, `opacity`, and a monotonic integer haptic trigger
in `@State`; read `accessibilityReduceMotion` from the environment. Route:

- drag release through `SwipeCardInteraction.commitDirection`,
- visible Keep through `.keep`,
- visible Queue for Deletion through `.delete`, and
- top-card named accessibility actions through those same direction calls.

The shared `commit(_:)` must call `commitGate.begin()` first, increment the
haptic trigger once, run the selected normal/reduced animation, await exactly
one supplied decision closure, then reset offset/opacity/gate for the next card.
Attach `.sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)` once
to the stack. A sub-threshold release animates only back to center and does not
increment the trigger or call a decision closure.

- [ ] **Step 4: Replace the old fixed gesture in `CleanerView`**

Replace the current `PrintedPhotoCard` and fixed ±60 point `DragGesture` with:

```swift
SwipeCardStack(
    cards: model.visibleCards,
    keepAction: { await model.keepCurrent() },
    queueAction: { await model.queueCurrentForDeletion() }
)
```

Place the visible Queue for Deletion and Keep buttons directly below the card
`ZStack` inside `SwipeCardStack`, so both invoke its private shared `commit(_:)`
method and cannot call the model separately. Retain their existing labels and
accessibility hints. Remove the old button row from `CleanerView`. Replace the
per-current-asset preview task with:

```swift
.task(id: model.currentAsset?.id) {
    await model.loadVisiblePreviews(pixelWidth: 900, pixelHeight: 900)
}
```

Keep progress, favorite label, undo, disabled album action, save/close behavior,
loading/error/complete states, and navigation unchanged.

- [ ] **Step 5: Run safety and full unit tests**

Run:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Expected: all unit tests pass; no test invokes a real photo library.

- [ ] **Step 6: Commit Task 4**

```sh
git add PhotoCleaner/Features/Cleaner/SwipeCardStack.swift \
  PhotoCleaner/Features/Cleaner/CleanerView.swift \
  PhotoCleanerTests/SafetyInvariantTests.swift
git commit -m "feat: add animated accessible cleaner stack"
```

---

### Task 5: Verification and status handoff

**Files:**
- Modify: `docs/STATUS.md`

**Interfaces:**
- Consumes: completed Tasks 1–4.
- Produces: exact automated verification record and remaining device checks.

- [ ] **Step 1: Run formatting and change-scope checks**

```sh
git diff --check
git status --short
git diff --stat HEAD~4
```

Expected: no whitespace errors; only planned Cleaner, test, design-system, and
status files are changed.

- [ ] **Step 2: Run the specified build command**

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build
```

Expected: exit code 0 and `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run all unit tests**

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Expected: exit code 0 and `** TEST SUCCEEDED **` with all unit tests passing.

- [ ] **Step 4: Record the UI-test result accurately**

Confirm target inventory with:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -list
```

Expected: app and unit-test targets only. Do not claim UI tests ran; record that
no UI-test target exists.

- [ ] **Step 5: Update `docs/STATUS.md`**

Record the exact build and test results and leave these manual iPhone 13 mini
checks open:

- 25-percent threshold feel and ±8-degree rotation cap,
- two rear cards fitting without hiding controls,
- first degraded/local preview remaining stable,
- placeholders never blocking interaction,
- visible button and VoiceOver action parity,
- Reduce Motion cross-fade,
- largest accessibility Dynamic Type,
- rapid repeated commit input,
- light haptic on a physical iPhone only.

- [ ] **Step 6: Run final verification after documentation change**

```sh
git diff --check
git status --short
```

Expected: no whitespace errors and only `docs/STATUS.md` remains uncommitted.

- [ ] **Step 7: Commit verification status**

```sh
git add docs/STATUS.md
git commit -m "docs: record swipe cleaner verification"
```
