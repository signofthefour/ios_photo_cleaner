import Photos

/// Bridges a callback-based `PHImageManager` request into a single async
/// result while staying safe under Swift concurrency cancellation.
///
/// Two races matter here:
/// - Task cancellation can arrive before `PHImageManager` has handed back a
///   request id; `register` and `cancel` share a lock so whichever happens
///   second cancels the request.
/// - `.opportunistic` delivery mode calls back twice (a fast low-quality
///   image, then a higher-quality one). The local-preview contract wants
///   only the first result, so `complete` runs its body once and cancels
///   the outstanding request afterward.
final class PhotoKitImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false
    private var didComplete = false

    func register(requestID: PHImageRequestID, imageManager: PHImageManager) {
        lock.lock()
        let shouldCancelImmediately = isCancelled
        if !shouldCancelImmediately {
            self.requestID = requestID
        }
        lock.unlock()

        if shouldCancelImmediately {
            imageManager.cancelImageRequest(requestID)
        }
    }

    func cancel(imageManager: PHImageManager) {
        lock.lock()
        isCancelled = true
        let requestID = self.requestID
        lock.unlock()

        if let requestID {
            imageManager.cancelImageRequest(requestID)
        }
    }

    func complete(imageManager: PHImageManager, _ body: () -> Void) {
        lock.lock()
        let alreadyCompleted = didComplete
        if !alreadyCompleted { didComplete = true }
        let requestID = self.requestID
        lock.unlock()

        guard !alreadyCompleted else { return }
        body()
        if let requestID {
            imageManager.cancelImageRequest(requestID)
        }
    }
}
