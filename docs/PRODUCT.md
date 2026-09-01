# Photo Cleaner Product Specification

## Product flow

1. On launch, inspect photo-library authorization.
2. Explain and request access when it has not been granted. Full and
   limited access both lead to Home; denial must not create a dead end.
3. From Home, continue a saved session, choose a month, choose an album,
   start a random review of the whole library, review pending deletion, or
   open Settings.
4. Before cleaning a chosen month or album, show the source's photo count
   and estimated review size. A random review has no fixed source to size
   in advance — it draws from the whole library in shuffled order.
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

### Image loading

The keep/delete decision does not depend on original-quality pixels, so
the card renders whichever image data PhotoKit already holds locally.
Requests must disable network access (`isNetworkAccessAllowed = false`)
so that reviewing a cloud-optimized asset never triggers an iCloud
download. If only a thumbnail or a degraded local rendition is cached,
that is what is shown; the app does not wait for or request original
quality.

### Card frame

Each card renders the photo inside a white border styled like a printed
photograph, with a heavier white margin along the bottom edge. That
bottom margin holds two data points as text: capture date (`dd/MM/yy`)
on the left, and location on the right. Both must also be exposed as
accessible labels, not conveyed by the frame graphic alone.

For the foundation implementation, location is displayed as locally
available latitude and longitude without reverse geocoding or any
network request. Missing metadata uses `Unknown date` and `No location`
in both visible and accessible text.

The foundation adds a mockable local-preview contract and deterministic
mock behavior. The production PhotoKit adapter that enforces
`isNetworkAccessAllowed = false` belongs to Milestone 2, when real photo
authorization and browsing are introduced.

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
   prefetching, and durable save/resume.
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
