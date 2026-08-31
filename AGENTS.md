# Photo Cleaner Engineering Instructions

## Product

This is a production, iPhone-only application for reviewing and cleaning
the user's photo library.

Users swipe right to keep a photo and left to add it to a pending
deletion queue. Swiping never permanently deletes a photo.

Users can toggle favorite status and add a photo to an existing or
new album. Sessions can start from timeline groups or albums and must
be resumable.

## Technical architecture

- Use SwiftUI.
- Target iPhone only.
- Use feature-based MVVM.
- Use PhotoKit for photo-library access.
- Use SwiftData only for session metadata.
- Never store private copies of the user's photos.
- Keep PhotoKit behind protocol-based services.
- Use structured concurrency.
- Keep UI state changes on the main actor.
- Make services injectable and mockable.

## Safety invariants

1. A swipe-left action only adds an identifier to a deletion queue.
2. Permanent deletion requires a separate review screen.
3. The deletion set must be visible before confirmation.
4. Failed or cancelled deletion must not be recorded as successful.
5. Destructive actions must never occur in tests against the real
   photo library.
6. Sessions must tolerate assets disappearing from the library.
7. Limited photo-library permission is a supported state.

## Accessibility

- Every swipe action must have an equivalent visible button or
  accessibility action.
- Support VoiceOver and Dynamic Type.
- Do not communicate favorite or deletion state using color alone.
- Use meaningful labels, values, and hints.

## Working rules

Before editing:

1. Read the relevant feature specification.
2. Inspect existing architecture and tests.
3. State which files will change.
4. Identify PhotoKit or persistence risks.
5. Wait if the requested behavior conflicts with a safety invariant.

During implementation:

- Keep changes within the requested milestone.
- Do not add unrelated dependencies.
- Do not redesign neighboring features.
- Add tests before or with implementation.
- Never claim an Xcode build passed without running it.

Before completion:

1. Run the specified build command.
2. Run unit tests.
3. Run relevant UI tests.
4. Report the commands and exact results.
5. List remaining simulator or physical-device checks.
