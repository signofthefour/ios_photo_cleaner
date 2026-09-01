# Swipe Card Stack Design

## Scope

Add the Product Specification's swipe interaction to the existing Cleaner on
the `feature/foundation` worktree. The change retains the printed-photo card,
mock/local-only preview boundary, session decision model, undo, progress, and
close/save behavior. It does not add PhotoKit, SwiftData, permanent deletion,
favorite mutation, album mutation, third-party dependencies, or a UI-test
target.

The interaction targets iPhone only, iOS 17 or newer, and the iPhone 13 mini
as the primary layout and verification device.

## Interaction

The Cleaner shows the current asset above as many as two following assets.
Rear cards use their first locally available preview when present and a
placeholder otherwise. They are slightly scaled and vertically offset so the
stack remains legible on a 5.4-inch display.

Dragging the top card moves it with the finger and rotates it proportionally
to horizontal displacement, capped at 8 degrees. A bordered `KEEP` stamp fades
in during a right drag and a bordered `DELETE` stamp fades in during a left
drag. The labels remain present so color is supplementary: keep uses green and
delete uses red.

On release, a drag commits when its horizontal displacement reaches 25 percent
of the measured card width. A committed card flies off-screen in its direction;
a sub-threshold card springs to center. A visible Keep button, visible Queue for
Deletion button, and the corresponding named accessibility actions use the same
commit path as the gesture. One light haptic occurs per committed decision,
never during dragging.

While a commit is in progress, the stack ignores further gesture, button, and
accessibility commits. The session decision is recorded exactly once after the
transition. If Reduce Motion is enabled, the fly-off and spring are replaced by
a short opacity transition; stamps and haptics remain unchanged.

## Architecture

`CleanerViewModel` remains the `@MainActor` owner of source assets, session
decisions, and preview loading. It exposes a window containing the current
asset and up to two successors. Preview state is keyed by asset identifier and
freezes the first completed result, including an unavailable result, so a later
or higher-quality rendition cannot replace what a card first displayed.

`SwipeCardStack` owns only transient presentation state: drag offset, commit
direction, animation state, interaction locking, Reduce Motion selection, and
haptic triggering. It calls the view model through keep and queue closures and
does not access the library service or session repository.

`SwipeCardInteraction` contains pure calculations for threshold comparison,
rotation, direction, and stamp opacity. Keeping these calculations independent
of SwiftUI permits deterministic boundary tests.

`PrintedPhotoCard` continues to render the preview and metadata. It gains an
optional visual stamp but retains its current combined accessibility value and
named Keep/Queue actions.

## Preview data flow

After loading a session or advancing/undoing, the Cleaner asks the view model
to load previews for the visible three-asset window. Requests may run
concurrently. A successful degraded preview is a complete first result and is
displayed immediately. A `nil`, failed, or cancelled request does not block the
interface; an unavailable placeholder is used. Cancellation caused by a view
or task ending is not converted into a user-facing failure.

The existing protocol describes a local preview request and persists no image
bytes. This milestone has no PhotoKit implementation. The future PhotoKit
adapter must set `PHImageRequestOptions.isNetworkAccessAllowed` to `false` and
must return its first local result without waiting for a higher-quality result.

## Safety and persistence

A left commit calls only the existing pending-delete session decision. It never
calls `deleteAssets`. Permanent deletion remains confined to the separate
deletion-review flow. Failed preview loading cannot prevent keep, queue, undo,
or close/save operations.

No preview, drag, animation, or haptic state is persisted. Existing session
metadata remains the sole saved state, so persistence schema and resume formats
do not change.

## Files

- Create `PhotoCleaner/Features/Cleaner/SwipeCardInteraction.swift` for pure
  gesture calculations and decision direction.
- Create `PhotoCleaner/Features/Cleaner/SwipeCardStack.swift` for layered card
  rendering and unified commit presentation.
- Modify `PhotoCleaner/Features/Cleaner/CleanerView.swift` to embed the stack
  and retain neighboring Cleaner controls.
- Modify `PhotoCleaner/Features/Cleaner/CleanerViewModel.swift` to expose the
  visible window and freeze first preview results by asset identifier.
- Modify `PhotoCleaner/Features/Cleaner/PrintedPhotoCard.swift` to render the
  accessible text stamp overlay.
- Modify `PhotoCleaner/DesignSystem/PhotoCleanerTheme.swift` to define the
  approved interaction and stack constants.
- Create `PhotoCleanerTests/SwipeCardInteractionTests.swift` for gesture math.
- Modify `PhotoCleanerTests/CleanerViewModelTests.swift` for visible-window and
  first-result preview behavior.
- Modify `PhotoCleanerTests/SafetyInvariantTests.swift` only if needed to make
  the shared commit-path deletion invariant explicit.
- Modify `docs/STATUS.md` after verification.

## Testing and verification

Tests are written before production changes and must first fail for the missing
behavior. Unit coverage includes the 25-percent threshold boundary, 8-degree
rotation cap, directional stamps and opacity, a maximum three-card window,
first-result preview freezing, stale-result isolation, duplicate-commit
protection where testable outside SwiftUI, and the guarantee that queueing does
not invoke deletion.

Run from `.worktrees/foundation`:

```sh
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' build

xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -destination 'platform=iOS Simulator,name=PhotoCleaner iPhone 13 mini' test
```

The project currently has no UI-test target. Manual iPhone 13 mini checks remain
for threshold feel, rear-card layout, button and VoiceOver parity, Reduce Motion,
Dynamic Type, rapid repeated input, preview placeholders, and physical-device
haptics.
