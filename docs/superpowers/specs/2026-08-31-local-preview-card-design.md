# Photo Cleaner Local Preview Card Design

## Scope

This change extends the safe mock foundation with a printed-photo Cleaner
card and a protocol-level contract for locally available previews. It does
not import PhotoKit, request photo access, download iCloud assets, persist
image bytes, reverse geocode coordinates, or permanently delete photos.

The production PhotoKit implementation is deferred to Milestone 2. That
adapter must set `PHImageRequestOptions.isNetworkAccessAllowed` to `false`.
The foundation contract and mock make the no-network behavior explicit and
testable without touching the real photo library.

Verification uses the `PhotoCleaner iPhone 13 mini` simulator running the
installed iOS 26.5 runtime.

## Domain model

`PhotoAsset` gains optional `latitude` and `longitude` values. Coordinates
remain framework-independent scalar values, so no CoreLocation or PhotoKit
type crosses into Domain. They are transient photo metadata and are not added
to `CleaningSession` persistence.

The Cleaner presentation derives two labels:

- Capture date formatted as `dd/MM/yy`, or `Unknown date` when absent.
- Coordinates formatted as a stable latitude/longitude pair, or
  `No location` when either coordinate is absent.

The same strings are used for visible content and accessibility values so
metadata is never communicated by the frame graphic alone.

## Local-preview boundary

`PhotoLibraryServiceProtocol` adds
`fetchLocalPreview(for: PhotoPreviewRequest) async throws -> LocalPhotoPreview?`.
`PhotoPreviewRequest` contains the asset identifier and target pixel width and
height as positive integers. Network access is not a caller option: the method
contract is local-only by definition.

`LocalPhotoPreview` contains an `isDegraded` flag and framework-independent
content. Content is either an SF Symbol name for deterministic foundation
mocks or encoded image `Data` for the future PhotoKit adapter. The value is
transient and is never written to the session repository or disk. A `nil`
result means no local rendition is available.

The deterministic mock records exact `PhotoPreviewRequest` values, returns
configured symbol previews, and performs no networking.

Milestone 2 will adapt this contract to `PHCachingImageManager`. Its request
options must disable network access, accept locally cached degraded results,
and never wait for original-quality pixels. A missing local rendition returns
the unavailable state rather than initiating an iCloud download.

## Cleaner data flow

When `CleanerViewModel` resolves the current asset, it separately requests a
local preview. Preview loading does not participate in decision state:

```text
current asset ID -> local-preview protocol -> transient card preview
        |
        +--------> CleaningSession decision -> metadata only
```

Keep, queue-for-deletion, undo, and save remain available if preview loading
fails or returns unavailable. Moving to another asset invalidates the prior
preview result so late asynchronous responses cannot replace the current
card.

## Card presentation

The Cleaner card uses a white printed-photo frame with equal top and side
margins and a visibly heavier bottom margin. The preview fills the inner
image area using aspect-fit behavior. An unavailable preview uses a neutral
photo placeholder inside the same frame.

The bottom margin contains capture date on the leading side and location on
the trailing side. Both support Dynamic Type, may wrap when necessary on the
iPhone 13 mini, and do not rely on fixed-height text containers.

The existing favorite label, progress, visible Keep and Queue buttons, swipe
gestures, equivalent accessibility actions, Undo, Album placeholder, and
Close & Save controls remain intact.

## Error and safety behavior

- A preview failure produces a placeholder and recoverable status; it never
  blocks or changes the session decision.
- Missing date or coordinates render the approved fallback text.
- No preview value is persisted by `InMemorySessionRepository`.
- Preview requests, swipes, buttons, undo, and save never call
  `deleteAssets(ids:)`.
- No reverse geocoding, iCloud download, or other network request occurs.
- Assets disappearing from the mock library continue through the existing
  unavailable-identifier path.

## Tests

Tests are written before implementation and cover:

- Exact `dd/MM/yy` date formatting with a fixed locale/calendar/time zone.
- `Unknown date` and `No location` fallbacks.
- Stable coordinate formatting without geocoding.
- Visible and accessibility-facing metadata using the same derived strings.
- Local-preview request recording and unavailable-preview behavior.
- Preview failure leaving Keep and Queue enabled and session state valid.
- Stale preview results not replacing a newer current asset.
- Preview loading and all non-confirmation Cleaner actions recording no
  deletion calls.

Final verification runs the static safety checks, full build, unit tests, and
any applicable UI tests against `PhotoCleaner iPhone 13 mini`.

## Deferred work

The following remain outside this change:

- PhotoKit authorization and real asset enumeration.
- The production `PHCachingImageManager` adapter.
- Reverse-geocoded place names.
- Persisted photo previews or private photo copies.
- Favorites, album mutation, and permanent deletion.
