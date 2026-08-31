# Photo Cleaner Milestone 1: Foundation Design

## Scope

Milestone 1 creates an iPhone-only SwiftUI foundation that demonstrates
the complete navigation shape with safe mock data. It does not import
PhotoKit, request photo access, permanently delete assets, use a real
photo library, or add third-party dependencies.

The deployment target is iOS 17 or newer. The checked-in native Xcode
project contains an iPhone app target and a unit-test target. Its initial
bundle identifier is `com.example.PhotoCleaner`, and simulator builds do
not require a development team.

## Project structure

```text
PhotoCleaner/
├── App/
│   ├── PhotoCleanerApp.swift
│   └── AppContainer.swift
├── Features/
│   ├── Home/
│   ├── SourcePicker/
│   ├── Cleaner/
│   ├── AlbumPicker/
│   ├── DeletionReview/
│   └── Settings/
├── Domain/
│   ├── Models/
│   └── Protocols/
├── Services/
│   └── MockPhotoLibraryService.swift
├── Persistence/
│   └── InMemorySessionRepository.swift
├── DesignSystem/
└── Resources/
PhotoCleanerTests/
```

## Architecture

Features use MVVM. SwiftUI views communicate with `@MainActor` view
models, which depend on injected protocols rather than framework-specific
services. `AppContainer` owns dependency implementations and constructs
feature view models. No view or view model accesses PhotoKit or SwiftData
directly.

The dependency flow is:

```text
SwiftUI view -> MainActor view model -> injected protocol -> mock service
```

Navigation uses typed routes for Home, source selection, Cleaner,
Deletion Review, and Settings. Feature folders own their view and view
model. Cross-feature data belongs in Domain rather than in a feature.

## Domain model

The minimum model includes:

- `PhotoAccessStatus`: not determined, limited, authorized, denied, and
  restricted.
- `TimelineGroup`: stable identifier, display title, date interval, and
  photo count.
- `PhotoAlbum`: stable identifier, title, and photo count.
- `PhotoAsset`: local identifier, creation date, favorite state, and mock
  preview reference. It contains no persisted image bytes.
- `CleaningSource`: a timeline group or album identified without leaking
  PhotoKit types.
- `PhotoDecision`: keep or pending deletion.
- `CleaningSession`: stable identifier, source, ordered asset identifiers,
  current position, decisions, pending deletion identifiers, unavailable
  identifiers, and timestamps.

Session invariants require pending deletion identifiers to correspond to
pending-delete decisions. Undo restores the most recent decision and its
previous position. Missing assets are skipped and recorded as unavailable.

## Protocol boundaries

`PhotoLibraryServiceProtocol` defines authorization, timeline and album
fetching, source asset fetching, favorite mutation, album assignment,
album creation, and deletion. Milestone 1 implements the full interface
with deterministic mock behavior, while destructive mock calls only
record invocations for assertions.

`SessionRepositoryProtocol` defines loading, saving, and removing the
current session. Milestone 1 uses an in-memory implementation. SwiftData
schema design and durable persistence belong to the milestone that first
requires relaunch resume behavior.

## Feature behavior

Home displays mock photo-access status, source actions, any saved session,
and pending-deletion status. Source Picker lists timeline groups and
albums with estimated counts. Cleaner displays mock asset metadata,
progress, keep and pending-delete controls, undo, and close/save. Deletion
Review shows the exact queued identifiers and permits restoration and
cancellation; its permanent-confirmation operation is visibly a safe mock.
Settings displays mock access state. Album Picker is represented in the
navigation structure but full interaction is deferred to Milestone 4.

Every stateful feature represents loading, content, empty, and recoverable
error states where applicable. Mock dependencies can simulate access
states, missing assets, and failures. Errors provide retry or a safe route
back without mutating destructive state.

## Accessibility

Keep and queue-for-deletion have visible buttons and accessibility actions
in addition to gestures. Controls have meaningful labels and hints. Text
supports Dynamic Type, and no state is communicated by color alone.

## Tests

Unit tests verify typed navigation, source selection, keep and
pending-delete decisions, undo, in-memory save/resume, missing-asset
handling, and the invariant that swipe decisions do not call deletion.
Tests use mocks exclusively and never interact with a real photo library.

When full Xcode is installed and selected, verification uses:

```sh
xcodebuild \
  -project PhotoCleaner.xcodeproj \
  -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

xcodebuild \
  -project PhotoCleaner.xcodeproj \
  -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

The exact installed simulator may be substituted after checking
`xcrun simctl list devices available`. This machine currently exposes
only Command Line Tools, so no iOS build can be claimed until full Xcode
is installed or selected.

## Explicit exclusions

Milestone 1 excludes real authorization, PhotoKit imports, SwiftData model
containers, durable sessions, real thumbnails, permanent deletion, album
mutation, UI-test automation, profiling, signing, and App Store metadata.
