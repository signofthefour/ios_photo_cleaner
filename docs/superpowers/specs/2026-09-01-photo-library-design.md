# Photo Library (PhotoKit) Design

## Scope

Add the real PhotoKit-backed implementation of `PhotoLibraryServiceProtocol`
on `feature/photo-library`, branched from `feature/foundation`. This
delivers PRODUCT.md's Milestone 2: real authorization, read-only
timeline/album browsing, and library-change observation, backed by the
actual photo library. (Library-change observation and the denied-access
recovery path described below were added later, on `feature/deletion-review`,
to actually close out Milestone 2 — see "Library-change observation".)

It does not add favorite mutation, album mutation, or permanent deletion.
Those protocol methods exist (the protocol is shared with the mock) but
throw `PhotoKitServiceError.notImplemented` rather than perform a real
mutation or silently no-op, since Milestones 4 and 5 own that behavior and
none of it is reachable from the UI yet. Session persistence stays
in-memory; durable resume remains a later milestone.

## Authorization

`requestAuthorization()` calls `PHPhotoLibrary.requestAuthorization(for:
.readWrite)`. Read-write is requested now (rather than read-only) so a
later milestone's favorite/album/delete mutations do not need a second
permission prompt. `PhotoKitAuthorizationMapping` is a pure, framework-free
mapping from `PHAuthorizationStatus` to the app's `PhotoAccessStatus`,
kept separate from the live service so it is unit-testable without a real
library or permission dialog.

`NSPhotoLibraryUsageDescription` was added to `Info.plist`; without it the
app would crash on the first authorization request.

## Browsing scope

- Only `PHAssetMediaType.image` assets are fetched. The product is named
  and specified throughout as a *photo* cleaner; video support is not
  currently specified and is left as a future decision rather than
  included silently.
- Albums are `PHAssetCollection` `.album`/`.albumRegular` only (user-created
  albums), matching the existing Source Picker's simple album list. Smart
  albums (Recents, Favorites, etc.) are excluded. Albums with zero photo
  assets are filtered out so Source Picker never offers a Start action that
  immediately shows "Review Complete".
- `PhotoTimelineGrouping` buckets assets by calendar month using
  `Calendar.current`, independent of PhotoKit, so it is unit-testable with
  fixture dates. Assets with no `creationDate` are grouped into a single
  `unknown-date` bucket labeled "Unknown Date"; its `TimelineGroup.interval`
  is a degenerate placeholder (`.distantPast`, zero duration) since it is
  never used to query — `fetchAssets(for:)` special-cases the
  `unknown-date` id with a `creationDate == nil` predicate instead of an
  interval comparison.
- `fetchAssets(for:)` re-queries PhotoKit by the group's stored date
  interval or the album's local identifier rather than caching membership,
  so results stay correct if the library changes between browsing and
  starting a session.

## Preview loading

`fetchLocalPreview(for:)` wraps `PHImageManager.requestImage` in a single
`async throws -> LocalPhotoPreview?`, matching the existing local-preview
contract:

- `PHImageRequestOptions.isNetworkAccessAllowed = false` always. A
  cloud-optimized asset is never downloaded to satisfy a swipe decision, per
  PRODUCT.md's Image Loading section.
- Delivery mode is `.opportunistic`, which can call back twice (a fast
  degraded image, then a higher-quality one). `PhotoKitImageRequestBox`
  runs the completion body only once and cancels the outstanding PhotoKit
  request afterward, so only the first locally available rendition is ever
  used — the existing `CleanerViewModel` freeze-first-result behavior is
  reinforced at the source rather than relied on alone.
- The same box resolves the task-cancellation race: if the calling task is
  cancelled before PhotoKit has returned a request id, cancellation is
  deferred and applied the instant the id is known, rather than dropped.
- A successful load is JPEG-encoded (`LocalPhotoPreviewContent
  .encodedImageData`) at 0.85 quality; encoded bytes are held only in
  memory for display; the local-preview contract still persists nothing.

## Library-change observation

`PhotoLibraryServiceProtocol` exposes `var libraryChanges: AsyncStream<Void>`.
Events carry no diff — every consumer just re-fetches whatever it's
currently showing, consistent with the rest of this service treating
PhotoKit as the source of truth rather than caching it.

`PhotoLibraryChangeBroadcaster` is the shared fan-out: each call to
`makeStream()` registers its own `AsyncStream` continuation (unbounded
buffering, so a `notify()` before a consumer starts iterating is not lost)
and removes itself via `onTermination` when that consumer's `Task` is
cancelled — which happens automatically when a SwiftUI `.task` subscribing
to it is torn down. `MockPhotoLibraryService` owns one directly, exposed as
`nonisolated var libraryChanges`, with a `simulateLibraryChange()` test
hook. `PhotoKitPhotoLibraryService` owns one too, but only registers itself
as a real `PHPhotoLibraryChangeObserver` with `PHPhotoLibrary.shared()` the
first time `libraryChanges` is accessed (never in `init`), and forwards
`photoLibraryDidChange` straight to the broadcaster; `deinit` unregisters.
Becoming a `PHPhotoLibraryChangeObserver` required making the service an
`NSObject` subclass, since that protocol demands `NSObjectProtocol`.

Two consumers, both wired as a plain `for await _ in ... { }` inside a
SwiftUI `.task` (auto-cancelled when the screen disappears, which is what
tears down the subscription):

- `CleanerViewModel.handleLibraryChange()` — the safety-relevant one.
  Re-fetches the session's source and re-runs the existing
  `skipUnavailableCurrentAssets()` helper, so a photo deleted elsewhere
  while a session is open is skipped like any other unavailable asset
  rather than leaving the Cleaner stuck. This directly serves AGENTS.md's
  "sessions must tolerate assets disappearing from the library" invariant
  for the *live*, mid-session case — `skipUnavailableCurrentAssets()`
  already handled the *resume* case (comparing against a stale saved
  session on `load()`).
- `SourcePickerViewModel.refreshIfNeeded()` — cosmetic freshness. Re-fetches
  timeline groups and albums *without* flipping back to the loading state,
  so counts update in place instead of flashing a spinner over already-
  visible content; guarded to only run from `.content`, and a failed
  refresh is silently ignored (`try?`) rather than replacing valid content
  with an error screen.

Both re-fetch methods swallow failures on purpose (`try?` / a plain
`guard let ... else { return }`): a background sync failing should never
disrupt whatever the user is already looking at.

## Denied-access recovery

PRODUCT.md's flow says "denial must not create a dead end." Two gaps this
closes:

- `SettingsView`'s copy still said "Milestone 1 uses safe mock photos and
  never requests access to your real library" — stale and, since the real
  PhotoKit adapter shipped, actively false. Replaced with accurate copy
  about what full/limited access enables and that deletion always needs a
  separate confirmation.
- Home now shows a banner when `accessStatus` is `.denied` or `.restricted`,
  read directly rather than added new state. Only `.denied` gets an "Open
  Settings" button (`UIApplication.openSettingsURLString` via
  `@Environment(\.openURL)`): `.restricted` is enforced externally
  (parental controls, MDM), so a Settings link would not let the user
  change anything, and `SettingsViewModel.canRecoverAccessInSettings`
  encodes that same distinction for the Settings screen's own button.

## What was not changed

`CleaningSession`, `CleanerViewModel`'s decision/undo/save logic,
`SwipeCardInteraction`, `PrintedPhotoCard`, and the visual design applied on
`feature/foundation` are untouched. `AppContainer` gained a `live` factory
alongside the existing `liveMock`; `PhotoCleanerApp` now composes `.live`.
`InMemorySessionRepository` is unchanged.

## Testing and verification

`PhotoTimelineGroupingTests` and `PhotoKitAuthorizationMappingTests` cover
the two pure, PhotoKit-adjacent pieces without needing a real library.
`PhotoLibraryChangeBroadcasterTests` covers the fan-out itself (delivery to
every active stream, no replay for a late subscriber, repeated
notifications each delivered) with plain `AsyncStream` mechanics, no
PhotoKit involved. `CleanerViewModelTests` and `SourcePickerViewModelTests`
cover `handleLibraryChange()`/`refreshIfNeeded()` against
`MockPhotoLibraryService` (using its new `setAssets(_:for:)`/`setAlbums(_:)`
mutators to simulate a changed library), including that a fetch failure
during either is silently absorbed. `PhotoKitPhotoLibraryService` itself
still cannot be meaningfully unit-tested: `PHAsset` has no public
initializer and authorization prompts cannot be driven headlessly, so its
correctness rests on this design's documented reasoning plus manual
on-device verification (also true of PhotoKit code in general, which is why
CLAUDE.md calls out "PhotoKit correctness" as an explicit review dimension
rather than a test-suite one).

Run from `.worktrees/photo-library`:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build

xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

Remaining manual checks: the real authorization prompt and Settings deep
link on-device or in the simulator (seeded with sample photos via the
simulator's Photos app), full/limited/denied/restricted flows, timeline and
album browsing against a real library, preview rendering for both cached
and cloud-optimized assets, confirming no network access occurs while
offline, deleting/adding a photo via the system Photos app while the
Cleaner and Source Picker are open to confirm live change observation
actually fires, and the denied-access banner's "Open Settings" button on a
real device.
