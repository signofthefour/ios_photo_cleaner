# Photo Library (PhotoKit) Design

## Scope

Add the real PhotoKit-backed implementation of `PhotoLibraryServiceProtocol`
on `feature/photo-library`, branched from `feature/foundation`. This
delivers PRODUCT.md's Milestone 2: real authorization, and read-only
timeline/album browsing backed by the actual photo library.

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

## What was not changed

`CleaningSession`, `CleanerViewModel`'s decision/undo/save logic,
`SwipeCardInteraction`, `PrintedPhotoCard`, and the visual design applied on
`feature/foundation` are untouched. `AppContainer` gained a `live` factory
alongside the existing `liveMock`; `PhotoCleanerApp` now composes `.live`.
`InMemorySessionRepository` is unchanged.

## Testing and verification

`PhotoTimelineGroupingTests` and `PhotoKitAuthorizationMappingTests` cover
the two pure, PhotoKit-adjacent pieces without needing a real library.
`PhotoKitPhotoLibraryService` itself cannot be meaningfully unit-tested:
`PHAsset` has no public initializer and authorization prompts cannot be
driven headlessly, so its correctness rests on this design's documented
reasoning plus manual on-device verification (also true of PhotoKit code in
general, which is why CLAUDE.md calls out "PhotoKit correctness" as an
explicit review dimension rather than a test-suite one).

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
and cloud-optimized assets, and confirming no network access occurs while
offline.
