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

## Subsequent milestones

- Milestone 2: PhotoKit authorization and browsing, limited-library support,
  library-change observation, and a production local-preview adapter with
  network access disabled.
- Milestone 3: production swipe-cleaner interaction, prefetching, and durable
  session behavior.
- Milestone 4: favorite and album mutation.
- Milestone 5: exact deletion review and separately confirmed PhotoKit deletion.
- Milestone 6: production hardening, profiling, localization, privacy metadata,
  and archive validation.

## Verification commands

Run from `.worktrees/foundation`:

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
  this session did not perform.
