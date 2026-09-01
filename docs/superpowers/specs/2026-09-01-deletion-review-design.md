# Deletion Review: Real Deletion Design

## Scope

Wire the existing Deletion Review screen's confirm action to PhotoKit's
real, permanent deletion on `feature/deletion-review` (branched from
`feature/photo-library`, skipping ahead of the not-yet-built Milestone 4).
This delivers PRODUCT.md's Milestone 5. It does not add favorite or album
mutation (still Milestone 4, still `.notImplemented`), and it does not
change how photos enter the pending-deletion queue — swipe-left still only
calls `CleaningSession.decide(.pendingDelete, ...)`.

## Safety invariants this satisfies

- A swipe-left action only ever adds an identifier to the queue:
  `CleanerViewModel.queueCurrentForDeletion()` is unchanged and still calls
  only `CleaningSession.decide`. `rg` confirms `deleteAssets` is called from
  exactly one place in `Features`: `DeletionReviewViewModel.confirmDeletion()`.
- Permanent deletion requires the separate Deletion Review screen, which
  already existed — this only replaces its mock confirmation with a real
  one.
- The deletion set is visible before confirming (the existing grid), and a
  new in-app `.confirmationDialog` asks again by exact count before
  `confirmDeletion()` runs. iOS itself also presents its own native
  confirmation for `PHAssetChangeRequest.deleteAssets` — the user confirms
  twice, once in-app and once from the system, independent of anything this
  app does.
- Failed or cancelled deletion is not recorded as successful:
  `DeletionReviewViewModel.confirmDeletion()` only mutates `pendingIDs`,
  `selectedIDs`, and the saved session's `pendingDeletionIDs` *after*
  `library.deleteAssets(ids:)` returns without throwing. A thrown error
  (including the user declining the native system alert) leaves the queue,
  session, and selection exactly as they were and surfaces a recoverable
  error message.
- Tests never touch a real photo library: the new
  `DeletionReviewViewModelTests` cases exercise `confirmDeletion()` only
  against `MockPhotoLibraryService`.

## Behavior

- `confirmDeletion()` deletes exactly `selectedIDs` (not all of
  `pendingIDs`) — selection already existed as a first-class concept
  (`selectAll`/`deselectAll`, gating the old mock confirm button), so this
  keeps that meaning rather than introducing a second one. There is
  currently no per-item selection toggle in the UI (`PRODUCT.md` only
  specifies bulk select/deselect all), so in practice this means "all" or
  "none" today; wiring a per-tile toggle was left out as it wasn't asked
  for and isn't spec'd.
- `PhotoKitPhotoLibraryService.deleteAssets(ids:)` fetches the assets by
  local identifier first. An id that no longer resolves to a real asset
  (already removed some other way) is not an error — nothing needs deleting
  for it, and the view model still resolves it out of the pending queue.
  Deletion itself is `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(...) }`,
  wrapped from its completion-handler API into `async throws`.
- `CleaningSession.markAssetsDeleted(ids:)` is the deletion-side counterpart
  to the existing `restorePendingDeletion(id:)`: it clears the matching
  decisions and removes the ids from `pendingDeletionIDs`, called only after
  the real deletion succeeds.
- A success or failure message is shown via `deletionSummaryMessage` /
  `deletionErrorMessage`, matching PRODUCT.md's "show a summary only after
  the system operation succeeds."

## What was not changed

`SwipeCardInteraction`, `CleanerViewModel`'s decision/undo/save logic, the
visual design, and the PhotoKit browsing/preview code from
`feature/photo-library` are untouched. `restore(id:)`, `selectAll()`,
`deselectAll()`, and `cancel()` behave exactly as before.

## Testing and verification

`DeletionReviewViewModelTests` covers: a successful deletion resolves the
queue and session and reports the right count; a forced library failure
(`MockPhotoLibraryError.forcedFailure`) leaves the queue, session, and
selection untouched and surfaces the error message; confirming with nothing
selected is a no-op. `SafetyInvariantTests` was updated only for the
constructor signature change (now takes `library:`); its assertion that
non-confirmation actions never call `deleteAssets` is unchanged and still
passes.

`PHAssetChangeRequest`/`PHPhotoLibrary.performChanges` cannot be unit
tested for the same reason noted in the photo-library design: no public
way to construct a fake `PHAsset` or drive the real library headlessly.
Manual verification is required before this ships:

Run from `.worktrees/deletion-review`:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build

xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Remaining manual checks: confirming deletion on-device against seeded
sample photos (both accepting and declining the native iOS alert), an id
that has already disappeared from the library by the time of confirming,
VoiceOver announcement of the in-app confirmation dialog and the
success/error alerts, and Dynamic Type at the largest accessibility size
for the new "Delete N Photos" button and dialogs.
