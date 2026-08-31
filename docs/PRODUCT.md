# Photo Cleaner Product Specification

## Product flow

1. On launch, inspect photo-library authorization.
2. Explain and request access when it has not been granted. Full and
   limited access both lead to Home; denial must not create a dead end.
3. From Home, continue a saved session, choose a timeline group, choose
   an album, review pending deletion, or open Settings.
4. Before cleaning, show the selected source's photo count and estimated
   review size.
5. During cleaning, swipe right to keep or left to queue for deletion.
   Visible buttons and accessibility actions provide equivalent controls.
6. Save the session when closing the cleaner.
7. Review the exact deletion set before asking PhotoKit to delete.
8. Show a summary only after the system operation succeeds.

## Cleaning session

Each photo card shows a full-size preview, date and time, favorite state,
album action, and progress. The user can keep, queue for deletion, toggle
favorite state, add the asset to albums, undo the latest decision, or
close and save.

A cleaning gesture changes session metadata only. It never deletes a
photo from the library.

## Album picker

The album picker supports search, existing-membership checkmarks, adding
to a selected album, and creating an album. Adding an asset to an album
does not remove it from any other album.

## Deletion review

The review grid shows every queued asset. Users can inspect full size,
restore individual assets, select or deselect all, cancel while retaining
the queue, or confirm the PhotoKit deletion request. Failed or cancelled
system operations leave session records intact.

## Resume data

Persist only source type and identifier, ordered PhotoKit local
identifiers, current position, decisions, pending-deletion identifiers,
and last-update time. Never persist copies of photos. Missing identifiers
are skipped safely and recorded as a library change.

## Milestones

1. Foundation: native SwiftUI project, dependency container, domain
   models and protocols, mocks, navigation, and unit tests.
2. Photo authorization and browsing: all access states, timeline and
   album browsing, empty/error states, and library-change observation.
3. Swipe cleaner: accessible gestures and buttons, undo, progress,
   prefetching, and save/resume using mock data.
4. Favorites and albums: optimistic favorite changes, searchable album
   picker, album creation, and assignment rollback.
5. Safe deletion: exact review set, restoration, confirmed batch request,
   unavailable-asset handling, and post-success session updates.
6. Production hardening: large/iCloud library behavior, memory pressure,
   interruption handling, localization, appearance and type scaling,
   privacy metadata, profiling, and archive validation.

Use one branch per milestone: `feature/foundation`,
`feature/photo-library`, `feature/swipe-cleaner`,
`feature/favorites-albums`, `feature/deletion-review`, and
`feature/production-hardening`.
