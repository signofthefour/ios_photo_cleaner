# Swipe Cleaner Persistence Design

## Scope

Close the one gap `docs/STATUS.md` calls out under Milestone 3: session
resume is still `InMemorySessionRepository` only, so a saved cleaning
session does not survive an app relaunch. This adds a SwiftData-backed
`SessionRepositoryProtocol` implementation on `feature/swipe-cleaner`,
branched from `feature/deletion-review`.

It does not touch the swipe interaction itself (gesture math, stamps,
undo, prefetching), which `docs/STATUS.md` already records as complete.
`CleaningSession`, `CleanerViewModel`, `DeletionReviewViewModel`, and every
other view model are unchanged: they depend only on
`SessionRepositoryProtocol`, so a new conforming type is the entire
change from their perspective.

## Storage shape

`CleaningSession` is already `Codable` (needed today for equality/test
fixtures) and framework-independent. Rather than mirror every field into
a second SwiftData schema — which would need to be kept in sync by hand
and duplicates a shape the domain model already owns — the persisted
model stores one encoded blob:

```swift
@Model
final class PersistedCleaningSession {
    var payload: Data
    init(payload: Data) { self.payload = payload }
}
```

`payload` is `JSONEncoder().encode(session)`. This still satisfies "Persist
no photo bytes": the encoded value contains only IDs, decisions, positions,
and dates — the same fields `docs/PRODUCT.md`'s "Resume data" section
already specifies — never a photo or preview.

The repository enforces the existing single-current-session invariant
(the same one `InMemorySessionRepository` and `SessionRepositoryProtocol`
already imply: one optional current session, not a history) by deleting
any existing row before inserting on `save`, rather than giving
`PersistedCleaningSession` an identity to upsert against. There is only
ever zero or one row.

## Repository

```swift
@ModelActor
actor SwiftDataSessionRepository: SessionRepositoryProtocol {
    func loadCurrent() async throws -> CleaningSession?
    func save(_ session: CleaningSession) async throws
    func removeCurrent() async throws
}
```

`@ModelActor` (SwiftData's macro) gives actor isolation around a
`ModelContext` it owns, matching the existing "keep observable UI state
and view models on the main actor, persistence off it" shape used by
`InMemorySessionRepository`. It is constructed from a `ModelContainer` the
caller owns, so tests can hand it an `isStoredInMemoryOnly: true`
container and production can hand it a real one — no different from how
`MockPhotoLibraryService` and `PhotoKitPhotoLibraryService` share one
protocol behind different backing stores.

## Composition

`AppContainer.liveMock` (used by every existing unit test and SwiftUI
preview) is unchanged: it keeps `InMemorySessionRepository`, so no test
gains a SwiftData dependency it didn't already have. `AppContainer.live`
gains a real `ModelContainer` for `PersistedCleaningSession`, built once
and reused:

```swift
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

A `ModelContainer` that fails to initialize means the on-disk store is
unusable; there is no safe partial-functionality fallback (an in-memory
stand-in would silently drop persistence, contradicting the point of this
change), so this fails loudly at launch rather than masking it — the same
tradeoff Apple's own SwiftData app template makes.

## Risks and tradeoffs

- **Schema evolution:** `CleaningSession`'s `Codable` shape has no
  versioning. If a later milestone adds a required field without a
  default, decoding an old saved payload throws, and `loadCurrent()`
  surfaces that through the existing `HomeViewModel`/`CleanerViewModel`
  recoverable-error paths (`"...could not be loaded. Please try again"`)
  rather than crashing — but nothing currently clears the corrupt row, so
  the error would recur every launch until a future migration or a manual
  "start fresh" affordance is added. Out of scope here: there is exactly
  one schema in play today (nothing to migrate from), and adding
  speculative versioning now has no current consumer.
- **Single-slot invariant:** delete-then-insert on every `save` is not
  transactional across two calls to the same repository from different
  tasks, but this matches the existing risk profile — `CleanerViewModel`
  and `DeletionReviewViewModel` already assume one in-flight session
  owner, same as with `InMemorySessionRepository`'s single stored-property
  slot.
- **No PhotoKit or CoreLocation involvement:** this change is entirely
  within `Persistence/`; it does not touch asset fetching, previews, or
  authorization, so none of the safety invariants around those are in
  play.

## Testing and verification

`SwiftDataSessionRepositoryTests` uses `ModelConfiguration(isStoredInMemoryOnly:
true)` — no on-disk state, consistent with "destructive actions must never
occur in tests against the real photo library" extended to persistence:
tests never touch a real store. It covers round-tripping a session across
two repository instances sharing one container (the actual behavior this
change adds over `InMemorySessionRepository` — surviving the owning
actor instance being recreated, standing in for an app relaunch), that a
second `save` replaces rather than accumulates, `removeCurrent` clearing
the stored row, and `loadCurrent` returning `nil` when nothing was ever
saved. Every existing view-model and safety test keeps using
`InMemorySessionRepository` unmodified.

Run from `.worktrees/swipe-cleaner`:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build

xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Remaining manual check: install the app, save a session mid-clean, force
quit, and relaunch to confirm the Cleaner resumes at the same position —
the one behavior this change adds that a unit test can approximate but
not fully replace.
