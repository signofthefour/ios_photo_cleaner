import Foundation

/// Fans out "the library changed" events to any number of independent
/// `AsyncStream` consumers. Each call to `makeStream()` gets its own
/// continuation so multiple view models can subscribe concurrently; a
/// consumer's stream is dropped automatically when its `Task` (typically a
/// SwiftUI `.task`) is cancelled.
///
/// Carries no diff information — consumers re-fetch whatever they care
/// about on each event, matching the app's local-only, no-caching-of-truth
/// approach to PhotoKit data.
final class PhotoLibraryChangeBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuationsByID: [UUID: AsyncStream<Void>.Continuation] = [:]

    func makeStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuationsByID[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    func notify() {
        lock.lock()
        let continuations = Array(continuationsByID.values)
        lock.unlock()

        for continuation in continuations {
            continuation.yield(())
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuationsByID.removeValue(forKey: id)
        lock.unlock()
    }
}
