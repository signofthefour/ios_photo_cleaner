# Project Status

Last updated: 2026-08-31 (Asia/Seoul)

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
- Hardened Cleaner exit handling so both custom back/close controls await the
  same guarded session save, remain onscreen after failure, and offer retry.
- Installed Xcode 26.6 and the iOS 26.5 simulator runtime. The approved build
  and test destination is `PhotoCleaner iPhone 13 mini`.

## Remaining foundation checks

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
