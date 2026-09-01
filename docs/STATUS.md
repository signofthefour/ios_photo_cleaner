# Project Status

Last updated: 2026-09-01 (Asia/Seoul)

## Completed

- Created the iPhone-only SwiftUI project and injectable feature-based MVVM
  foundation on `feature/foundation`.
- Added typed navigation for Home, source selection, Cleaner, deletion review,
  and Settings using deterministic mock services.
- Added framework-independent cleaning-session models, safe Keep and pending-
  deletion decisions, undo, missing-asset handling, and in-memory save/resume.
- Added the local-only preview protocol and deterministic mock behavior without
  PhotoKit, CoreLocation, SwiftData, networking, geocoding, or persisted preview
  bytes.
- Added the printed Cleaner card with deterministic date/location labels,
  unavailable-preview handling, Dynamic Type-friendly metadata, visible and
  accessible Keep/Queue equivalents, and status-aware VoiceOver values.
- Added the Cleaner card stack with a width-relative 25-percent commit
  threshold, capped 8-degree rotation, text-and-color KEEP/DELETE stamps, two
  locally backed rear cards, unified gesture/button/accessibility commits,
  duplicate-commit protection, a light commit haptic, and a Reduced Motion
  cross-fade.
- The Cleaner requests the visible three-card preview window concurrently,
  accepts a degraded local rendition immediately, and freezes the first result
  for each asset rather than waiting for or replacing it with higher quality.
- Hardened Cleaner exit handling so both custom back/close controls await the
  same guarded session save, remain onscreen after failure, and offer retry.
- Installed Xcode 26.6 and the iOS 26.5 simulator runtime. The approved build
  and test destination is `PhotoCleaner iPhone 13 mini`.
- Applied a warm, printed-photo visual design across Home, Source Picker,
  Cleaner, and Deletion Review: a shared `PhotoCleanerTheme.Palette` (warm
  background/surface/ink tones plus keep/delete accents), a reusable
  `CleanerCircularButtonStyle` for Undo/Delete/Keep/Album controls, a Cleaner
  progress bar backed by a new `CleanerViewModel.progressFraction`, and
  restyled rows/tiles/grid tiles on the other three screens. No view-model
  public API, session/decision logic, gesture math, or accessibility
  labels/hints/actions changed; only presentation.

- Added the real PhotoKit-backed `PhotoLibraryServiceProtocol` implementation
  on `feature/photo-library` (branched from `feature/foundation`):
  `PHPhotoLibrary.requestAuthorization(for: .readWrite)` for authorization,
  month-bucketed timeline groups (image assets only) via the pure
  `PhotoTimelineGrouping`, user-album browsing via `PHAssetCollection`
  (`.albumRegular`, non-empty only), and a cancellation-safe local-preview
  loader (`isNetworkAccessAllowed = false`, first `.opportunistic` result
  only). `NSPhotoLibraryUsageDescription` added to `Info.plist`.
  `setFavorite`/`addAsset`/`createAlbum`/`deleteAssets` intentionally throw
  `.notImplemented` — those are Milestones 4 and 5, and none are reachable
  from the UI yet. `PhotoCleanerApp` now composes `AppContainer.live`. See
  `docs/superpowers/specs/2026-09-01-photo-library-design.md`.

- Added real permanent deletion on `feature/deletion-review` (branched from
  `feature/photo-library`): Deletion Review's confirm action now calls
  `PhotoKitPhotoLibraryService.deleteAssets(ids:)` (real
  `PHAssetChangeRequest.deleteAssets` via `PHPhotoLibrary.performChanges`),
  behind a new in-app `.confirmationDialog` in addition to iOS's own native
  delete confirmation. `CleaningSession.markAssetsDeleted(ids:)` resolves
  successfully deleted ids out of the pending queue; a failed or cancelled
  deletion leaves the queue, session, and selection unchanged and shows a
  recoverable error. `favorite`/`album` mutation remain `.notImplemented`.
  See `docs/superpowers/specs/2026-09-01-deletion-review-design.md`.

- Added a "Give Me Random" mode and renamed "Clean by Date" to "Clean by
  Month" (the grouping was already month-based; this was a label fix, not a
  behavior change). `CleaningSource` gained a `.random` case; Home navigates
  straight to the Cleaner with it, bypassing Source Picker since there is
  nothing to pick. `PhotoKitPhotoLibraryService.fetchAssets(for: .random)`
  fetches the whole image library and shuffles it via the pure, seed-testable
  `RandomPhotoOrdering`. No other Cleaner/session logic changed — a random
  session behaves exactly like a month or album session once assets are
  loaded.

- Fixed a resume/continue gap: a finished review (every asset decided) was
  still offered as "Continue Cleaning" from Home, and revisiting its exact
  source in the Cleaner just resumed the exhausted position, showing "Review
  Complete" immediately. Added `CleaningSession.isComplete`; `HomeViewModel`
  now only exposes a saved session for "Continue" when it isn't complete,
  and `CleanerViewModel.load()` only resumes a saved session when it matches
  the requested source *and* isn't complete — otherwise it starts a fresh
  session. Because the single-slot session repository couples the review
  position with the pending-deletion queue, starting fresh now explicitly
  carries the previous session's `pendingDeletionIDs` forward (this also
  fixes an existing bug where switching to a different source silently
  dropped whatever was already queued for deletion). Pending Deletion's
  count is read independent of completion either way, so it's unaffected.

- Closed out Milestone 2 (it was previously incomplete: authorization and
  browsing worked, but library-change observation was entirely missing, and
  denied access was a dead end). Added `PhotoLibraryServiceProtocol
  .libraryChanges: AsyncStream<Void>`, backed by a new
  `PhotoLibraryChangeBroadcaster` shared by both `MockPhotoLibraryService`
  and `PhotoKitPhotoLibraryService` (the latter now an `NSObject` subclass
  conforming to `PHPhotoLibraryChangeObserver`, registering lazily on first
  access). `CleanerViewModel.handleLibraryChange()` re-fetches and re-runs
  the existing unavailable-asset handling when the library changes mid-
  session (the live counterpart to the resume-time check that already
  existed); `SourcePickerViewModel.refreshIfNeeded()` silently refreshes
  counts without a loading flash. Also fixed `SettingsView`'s stale
  "Milestone 1 uses mock photos" copy (false since the PhotoKit adapter
  shipped) and added a denied-access recovery path: Home now shows a
  banner for `.denied`/`.restricted` access, with an "Open Settings" button
  for `.denied` (`.restricted` is externally enforced, so no button).
  See `docs/superpowers/specs/2026-09-01-photo-library-design.md`.

- Closed out Milestone 3 on `feature/swipe-cleaner` (branched from
  `feature/deletion-review`): sessions are now durably persisted via
  SwiftData instead of `InMemorySessionRepository`. `PersistedCleaningSession`
  stores one JSON-encoded `CleaningSession` blob (no photo bytes — the same
  fields `docs/PRODUCT.md`'s "Resume data" section already specifies); the
  new `SwiftDataSessionRepository` (`@ModelActor`) deletes any existing row
  before inserting on `save`, preserving the existing single-current-session
  invariant. `AppContainer.live` now builds a real `ModelContainer` for
  it; `AppContainer.liveMock` and every existing test are unchanged and
  keep using `InMemorySessionRepository`. See
  `docs/superpowers/specs/2026-09-01-swipe-cleaner-persistence-design.md`.

- Added a "Restore All" action to Deletion Review: `CleaningSession
  .restoreAllPendingDeletions()` clears the entire pending-deletion queue
  and its decisions in one step, and `DeletionReviewViewModel.restoreAll()`
  saves the result. Deliberately independent of `selectedIDs` (which only
  governs what a subsequent `confirmDeletion()` would permanently delete)
  so restoring can never act on the wrong set depending on what's checked
  for deletion.

- Fixed a real bug surfaced by manual on-device testing: restoring a
  single photo from Pending Deletion silently did nothing whenever that
  photo's pending-deletion status had been carried forward from a
  previous, completed session for the same source. `CleanerViewModel
  .load()` carried `pendingDeletionIDs` forward into the fresh session but
  not the matching `.pendingDelete` entries in `decisions`, so
  `restorePendingDeletion(id:)`'s `decisions[id] == .pendingDelete` guard
  silently no-op'd. Fixed by seeding `decisions` alongside the carried-
  forward ids; added `CleanerViewModelTests
  .testCarriedForwardPendingDeletionCanStillBeRestored()`, which
  reproduces the exact scenario end-to-end (carry-forward, then restore
  through `DeletionReviewViewModel`) and would have caught this before
  it shipped. Audited every other `CleaningSession` construction and
  mutating method afterward — no other invariant mismatch found.

- Delivered Milestone 4 on `feature/favorites-albums` (branched from
  `main`): `PhotoKitPhotoLibraryService.setFavorite`/`addAsset`/
  `createAlbum` are real `PHAssetChangeRequest`/
  `PHAssetCollectionChangeRequest` calls instead of `.notImplemented`
  stubs. `PhotoLibraryServiceProtocol` gained
  `albumIDs(containingAssetID:)` (via `PHAssetCollection
  .fetchAssetCollectionsContaining(_:with:options:)`) for the album
  picker's existing-membership checkmarks. The Cleaner's favorite label
  is now a button (`CleanerViewModel.toggleFavorite()`: optimistic flip,
  rolls back and shows a recoverable error on failure), and its Album
  button opens a new `AlbumPickerView` sheet — search, existing-
  membership checkmarks, add (optimistic with the same rollback
  pattern), and album creation (which auto-adds the current photo, since
  that's the reason the sheet was opened). Deletion and session logic
  are untouched. See
  `docs/superpowers/specs/2026-09-01-favorites-albums-design.md`.

- Closed out Milestone 5's last open item: unavailable-asset handling in
  Deletion Review had already been implemented (`PhotoKitPhotoLibraryService
  .deleteAssets` only fetches ids that still resolve to a `PHAsset` and
  succeeds regardless of ids that don't) but had no test coverage, since
  the mock had no way to model an id no longer existing.
  `MockPhotoLibraryService.deleteAssets` now mirrors the real
  implementation's exact shape — filter out ids marked missing via the
  new `setMissingAssetIDs(_:)`, then succeed even if that leaves nothing
  left to delete — and two new `DeletionReviewViewModelTests` cases
  confirm a disappeared id (and every id disappearing at once) still
  resolves out of the pending queue rather than surfacing as a failure.

## Remaining foundation checks

- Complete manual iPhone 13 mini checks for the 25-percent threshold feel,
  capped rotation, two-card rear stack fit, placeholder interaction, and stable
  first/degraded previews.
- Verify visible-button and VoiceOver-action parity, Reduce Motion cross-fades,
  rapid repeated commit input, and largest accessibility Dynamic Type on the
  iPhone 13 mini simulator.
- Verify the light commit haptic on a physical iPhone; simulator tests cannot
  validate haptic feel.
- Complete manual iPhone 13 mini checks for the custom close/save failure and
  retry experience, VoiceOver announcements, largest accessibility Dynamic
  Type, metadata wrapping, rapid decisions, dark appearance, and absence of
  photo-permission or network prompts.
- Add a UI-test target in a later hardening milestone if automated end-to-end
  navigation and accessibility interaction coverage is required. The current
  project contains only the app and unit-test targets.

## Milestone status

Work has not proceeded strictly in order — Milestone 3's interaction and
much of Milestone 5 were built before Milestone 4 — so this reflects actual
status per milestone rather than "what's left, in order."

- Milestone 1 (Foundation): complete.
- Milestone 2 (Photo authorization and browsing): complete as of this
  session — all access states, timeline/album browsing, empty/error
  states, and library-change observation are in place. `.limited` access
  is handled like `.authorized` throughout; no separate "select more
  photos" affordance was built for it.
- Milestone 3 (Swipe cleaner): complete as of this session. The
  interaction itself — gesture math, stamps, undo, progress, and
  prefetching the visible three-card window — was built ahead of
  schedule on `feature/foundation`; durable session persistence (SwiftData)
  was added on `feature/swipe-cleaner` to close the gap.
- Milestone 4 (Favorites and albums): complete as of this session.
  `setFavorite`/`addAsset`/`createAlbum` are real, and the Cleaner's
  favorite toggle and Add to Album sheet are wired up and reachable.
- Milestone 5 (Safe deletion): complete as of this session — exact
  review set, restoration, a confirmed real PhotoKit delete request
  (behind both an in-app and the native iOS confirmation), post-success
  session updates, and unavailable-asset handling. The last item
  (an id that disappears from the library between being queued and
  being confirmed) was already implemented correctly but had zero test
  coverage, since `MockPhotoLibraryService.deleteAssets` had no concept
  of an id no longer existing. It now mirrors the real implementation's
  exact shape (silently drop ids that don't resolve, succeed regardless,
  including when that leaves nothing to actually delete), seedable via
  `setMissingAssetIDs(_:)`; on-device confirmation with a real
  disappearing asset remains a manual check.
- Milestone 6 (Production hardening): not started.

## Verification commands

Run from `.worktrees/swipe-cleaner` (the current tip of the
foundation → photo-library → deletion-review → swipe-cleaner branch
chain):

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

## Latest verification

Verified on 2026-09-01 using Xcode 26.6 and the `PhotoCleaner iPhone 13 mini`
simulator, after the visual design pass on `feature/foundation`:

- The specified build command exited 0 with `** BUILD SUCCEEDED **`.
- The specified unit-test command exited 0 with `** TEST SUCCEEDED **`; 43
  tests passed with zero failures (41 prior plus 2 new `progressFraction`
  tests).
- `rg` confirmed no `PhotoKit`/`SwiftData` imports and no `deleteAssets` calls
  outside `Services`.
- Installed the built app on `PhotoCleaner iPhone 13 mini` and screenshotted
  Home, confirming the new layout renders correctly on-device. Source Picker,
  Cleaner, and Deletion Review were verified by build/test success and code
  review only; manually walking every screen on-device remains a remaining
  check below.
- No UI-test target exists, so automated UI tests were not run.

Verified again on 2026-09-01 on `feature/photo-library`, after adding the
PhotoKit adapter:

- Build and unit-test commands both exited 0 (`** BUILD SUCCEEDED **`,
  `** TEST SUCCEEDED **`); 49 tests passed with zero failures (43 prior plus
  6 new: `PhotoTimelineGroupingTests` and `PhotoKitAuthorizationMappingTests`).
- `rg` confirmed no `SwiftData` imports, no `deleteAssets`/`setFavorite`/
  `addAsset`/`createAlbum` calls outside `Services`, and that
  `isNetworkAccessAllowed = false` is present in the preview-loading code.
- Not yet verified: the real authorization prompt and every access-state
  outcome, timeline/album browsing against an actual seeded library, preview
  rendering for cached vs. cloud-optimized assets, and confirming no network
  access while offline — all require interactive on-device/simulator use
  this session did not perform. The authorization prompt itself was
  confirmed on the simulator (correct privacy string, real library
  contents), but tapping through it requires interactive input this session
  could not script.

Verified again on 2026-09-01 on `feature/deletion-review`, after wiring real
deletion:

- Build and unit-test commands both exited 0 (`** BUILD SUCCEEDED **`,
  `** TEST SUCCEEDED **`); 52 tests passed with zero failures (49 prior plus
  3 new `DeletionReviewViewModelTests` cases for success, failure, and
  nothing-selected).
- `rg` confirmed `deleteAssets` is called from exactly one place in
  `Features` (`DeletionReviewViewModel.confirmDeletion()`), no
  `setFavorite`/`addAsset`/`createAlbum` calls outside `Services`, and no
  `SwiftData` imports.
- Not yet verified: real on-device deletion (accepting and declining both
  the in-app and native iOS confirmations), an id that disappears from the
  library before confirming, and VoiceOver/Dynamic Type on the new dialogs
  and button — all require interactive input this session could not
  script.
- Also verified on `feature/deletion-review` after adding real Deletion
  Review thumbnails (`DeletionReviewViewModel.loadPreviews`), the Cleaner's
  `.onDisappear` safety-net save, and the "Give Me Random" mode plus the
  "Clean by Month" rename: build and unit-test commands both exited 0; 58
  tests passed with zero failures (52 prior plus 2 preview-loading cases, 1
  `.random`-source case, and 3 `RandomPhotoOrderingTests`). `rg` re-confirmed
  `deleteAssets` is still called from exactly one place and no `SwiftData`
  imports exist. Not yet verified: real thumbnails and the onDisappear save
  on-device, and "Give Me Random" against a real shuffled library — all
  require interactive input this session could not script.

Verified again after the completed-session resume fix: build and unit-test
commands both exited 0; 63 tests passed with zero failures (58 prior plus 2
`CleaningSession.isComplete` cases, 2 `CleanerViewModel` cases covering
same-source and cross-source pending-deletion carry-forward, and 1
`HomeViewModel` case). Not yet verified on-device: finishing a real session,
confirming Home no longer offers "Continue," and confirming a fresh session
starts on revisiting that source.

Verified again after closing out Milestone 2 (library-change observation,
Settings copy fix, denied-access recovery): build and unit-test commands
both exited 0; 71 tests passed with zero failures (63 prior plus 3
`PhotoLibraryChangeBroadcasterTests`, 2 `CleanerViewModel` library-change
cases, and 3 `SourcePickerViewModel` refresh cases). `rg` re-confirmed
`deleteAssets` is still called from exactly one place and no `SwiftData`
imports exist. Not yet verified on-device: deleting/adding a photo via the
system Photos app while the Cleaner or Source Picker is open, and the
denied-access "Open Settings" button actually opening the app's Settings
page.

Verified again on 2026-09-01 on `feature/swipe-cleaner`, after adding
SwiftData session persistence: build and unit-test commands both exited 0
(`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`); 75 tests passed with
zero failures (71 prior plus 4 new `SwiftDataSessionRepositoryTests`
cases: empty load, round-trip across repository instances sharing a
container, save-replaces-not-accumulates, and remove-clears). `rg`
confirmed `import SwiftData` appears only under `Persistence/` and in
`App/AppContainer.swift`, nowhere in `Domain`, `Features`, or `Services`.
Not yet verified on-device: starting a session, force-quitting before
closing the Cleaner, and confirming a relaunch resumes at the same
position and pending-deletion queue — the actual behavior this change
adds, which a unit test can only approximate by simulating a fresh
repository instance against a shared container.

Verified again after adding "Restore All" to Deletion Review: build and
unit-test commands both exited 0 (`** BUILD SUCCEEDED **`,
`** TEST SUCCEEDED **`); 78 tests passed with zero failures (75 prior plus
2 new `CleaningSessionTests` cases for `restoreAllPendingDeletions()` and
1 new `DeletionReviewViewModelTests` case confirming it clears the queue
and saves regardless of the current `selectedIDs`). `rg` confirmed
`deleteAssets` is still called from exactly one place. Not yet verified
on-device: the "Restore All" button against a real queued session and
VoiceOver/Dynamic Type on the new toolbar button.

Verified again after the carried-forward-restore bugfix, this time
actually on-device: this bug was found from real interactive testing on
the `PhotoCleaner iPhone 13 mini` simulator (tapping Restore visibly did
nothing), traced to root cause by inspecting the actual persisted
SwiftData store's payload, fixed, then confirmed by re-running the same
manual repro on the simulator with a rebuilt app after patching the
already-corrupted on-disk session to match. Build and unit-test commands
both exited 0; 79 tests passed with zero failures (78 prior plus 1 new
`CleanerViewModelTests` case). Still not yet verified on-device: haptics,
VoiceOver, Dynamic Type, and a full force-quit/relaunch resume check.

Verified again after delivering Milestone 4: build and unit-test commands
both exited 0 (`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`); 92 tests
passed with zero failures (79 prior plus 2 new `MockServicesTests` cases,
2 new `CleanerViewModelTests` cases, and 9 new
`AlbumPickerViewModelTests` cases). `rg` confirmed `deleteAssets` is
still called from exactly one place and `SwiftData` imports remain
confined to `Persistence/` and `AppContainer.swift`.
`PhotoKitPhotoLibraryService`'s three real mutation implementations and
`albumIDs(containingAssetID:)` remain untestable in isolation (`PHAsset`/
`PHAssetCollection` have no public initializer), same as `deleteAssets`
already was — correctness rests on code review plus the manual checks
below. Not yet verified on-device: real favorite toggle (including a
forced-failure path, which needs an actual PhotoKit error and isn't
scriptable), the album picker's search and existing-membership
checkmarks against real album contents, album creation, and
VoiceOver/Dynamic Type on the new sheet.

Verified again after closing out Milestone 5's unavailable-asset-handling
test gap: build and unit-test commands both exited 0
(`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`); 94 tests passed with
zero failures (92 prior plus 2 new `DeletionReviewViewModelTests` cases).
`rg` confirmed `deleteAssets` is still called from exactly one place.
Not yet verified on-device: deleting a queued photo via the system
Photos app while Deletion Review is open, then confirming, to see the
real behavior this test models.
