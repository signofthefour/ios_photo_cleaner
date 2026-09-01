# Favorites and Albums Design

## Scope

Delivers PRODUCT.md's Milestone 4 on `feature/favorites-albums`, branched
from `feature/swipe-cleaner`'s merged history on `main`: favorite toggling
from the Cleaner, and an album picker (search, existing-membership
checkmarks, add, create) reachable from the Cleaner's Album button.
`setFavorite`, `addAsset`, and `createAlbum` already exist on
`PhotoLibraryServiceProtocol` and throw `.notImplemented` in
`PhotoKitPhotoLibraryService` — this replaces those with real
implementations and wires them to the UI for the first time.

Deletion stays exactly as Milestone 5 left it; nothing here touches
`deleteAssets`, `DeletionReviewViewModel`, or `CleaningSession`.

## Protocol addition

The album picker needs to show existing-membership checkmarks (PRODUCT.md),
which requires knowing which albums the *current* asset already belongs
to. `fetchAlbums()` returns bare `PhotoAlbum` values (id/title/count) with
no per-asset membership, so `PhotoLibraryServiceProtocol` gains:

```swift
func albumIDs(containingAssetID assetID: String) async throws -> Set<String>
```

Real implementation uses `PHAssetCollection
.fetchAssetCollectionsContaining(_:with:options:)` — a single PhotoKit
call for exactly this question, filtered to `.albumRegular` to match
`fetchAlbums()`'s own filtering. The mock tracks membership as
`[albumID: Set<assetID>]`, updated by `addAsset` and seedable directly by
tests via `setAlbumMembership(_:for:)`.

## Favorite toggle (Cleaner)

The existing footnote under the card (`Label(asset.isFavorite ? ...)`)
becomes a button. `CleanerViewModel.toggleFavorite()`:

1. Flips `isFavorite` on the matching entry in `assets` immediately —
   the UI updates before the network round-trip, per PRODUCT.md's
   "optimistic favorite changes."
2. Calls `library.setFavorite(_:assetID:)`.
3. On failure, flips it back and sets `favoriteErrorMessage`, surfaced
   through the same alert pattern `saveErrorMessage` already uses.

This mirrors `DeletionReviewViewModel.restore`'s shape (mutate, persist,
roll back only the local state on failure) but there is no session
mutation here at all — favorite status lives entirely in PhotoKit, not
in `CleaningSession`.

## Album picker

New feature, `Features/AlbumPicker/`, presented as a sheet from the
Cleaner's Album button (not a pushed `AppRoute`): it's scoped to "add
*this* asset to an album" for whichever asset is currently on top of the
stack, not a standalone screen anything else navigates to, so it doesn't
need a typed route or back-stack entry. `CleanerViewModel
.makeAlbumPickerViewModel(assetID:)` constructs it, reusing the same
`library` the Cleaner already holds — no `AppContainer` involvement,
matching how the Cleaner already owns its one dependency set.

`AlbumPickerViewModel` mirrors `SourcePickerViewModel`'s
loading/content/empty/failed `State` shape:

```swift
enum State: Equatable {
    case loading
    case content(albums: [PhotoAlbum])
    case empty
    case failed(message: String)
}
```

- `load()` fetches `fetchAlbums()` and `albumIDs(containingAssetID:)`
  concurrently (`async let`, matching `SourcePickerViewModel.refresh()`).
- `searchText` filters the loaded albums by case-insensitive title
  containment; search never re-fetches, matching the offline-filter
  pattern implied by "supports search" being a picker-local concern in
  PRODUCT.md, not a PhotoKit predicate.
- `add(to:)` is optimistic like the favorite toggle: the checkmark for
  that album appears immediately, `addAsset` is called, and a failure
  removes the checkmark and sets `errorMessage` — this is exactly
  PRODUCT.md's Milestone 4 "assignment rollback."
- `createAlbum(named:)` creates the album, inserts it into the loaded
  list (re-sorted to match `fetchAlbums()`'s own
  title-ordering), and then immediately calls `add(to:)` for it. The
  screen exists to add the current photo somewhere — creating an album
  and not adding the photo to it would need a redundant second tap for
  the one thing the user opened this screen to do.

Adding to an album the asset already belongs to is a no-op (`add(to:)`
returns early), matching PRODUCT.md's "adding to an album does not
remove it from any other album" — repeat taps are harmless rather than
toggling membership off.

## What was not changed

`CleaningSession`, `DeletionReviewViewModel`, `SourcePickerViewModel`,
and the swipe/undo/save mechanics are untouched. `deleteAssets` remains
the only mutation Deletion Review can trigger. `PhotoAsset.isFavorite`
was already read correctly from real PhotoKit (`Self.photoAsset(from:)`
already set it from `asset.isFavorite`); only the *write* path was
missing.

## Testing and verification

`MockPhotoLibraryService` gains `setAlbumMembership(_:for:)` (test-only
seeding, distinct from the recorded `albumAssignments` audit log so
seeding initial state doesn't pollute assertions about what a test
itself triggered). `AlbumPickerViewModelTests` covers load, search
filtering, add-then-membership-reflected, failed-add-rolls-back,
create-then-auto-adds, and failed-create. `CleanerViewModelTests` gains
optimistic-toggle and failed-toggle-rolls-back cases.
`PhotoKitPhotoLibraryService`'s three real implementations remain
untestable in isolation for the same reason `deleteAssets` already is
(`PHAsset`/`PHAssetCollection` have no public initializers) — correctness
rests on this design plus manual on-device verification, consistent with
CLAUDE.md's "PhotoKit correctness" being a review dimension rather than a
test-suite one.

Run from `.worktrees/favorites-albums`:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build

xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Remaining manual checks: real favorite toggle against a seeded simulator
library (including a forced-failure path, which requires a real error —
not scriptable), the album picker's search, existing-membership
checkmarks against real album contents, album creation, and
VoiceOver/Dynamic Type on the new sheet.
