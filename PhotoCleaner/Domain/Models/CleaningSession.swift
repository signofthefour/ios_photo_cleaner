import Foundation

struct CleaningSession: Hashable, Codable, Sendable {
    let id: UUID
    let source: CleaningSource
    let orderedAssetIDs: [String]
    private(set) var currentPosition: Int
    private(set) var decisions: [String: PhotoDecision]
    private(set) var pendingDeletionIDs: [String]
    private(set) var unavailableAssetIDs: [String]
    let createdAt: Date
    private(set) var updatedAt: Date

    private var undoHistory: [String] = []

    init(
        id: UUID,
        source: CleaningSource,
        orderedAssetIDs: [String],
        currentPosition: Int,
        decisions: [String: PhotoDecision],
        pendingDeletionIDs: [String],
        unavailableAssetIDs: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.source = source
        self.orderedAssetIDs = orderedAssetIDs
        self.currentPosition = currentPosition
        self.decisions = decisions
        self.pendingDeletionIDs = pendingDeletionIDs
        self.unavailableAssetIDs = unavailableAssetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func decide(_ decision: PhotoDecision, assetID: String) throws {
        guard let assetIndex = orderedAssetIDs.firstIndex(of: assetID) else {
            throw SessionDecisionError.unknownAsset
        }
        guard assetIndex == currentPosition else {
            throw SessionDecisionError.outOfOrderAsset
        }

        decisions[assetID] = decision
        if decision == .pendingDelete {
            pendingDeletionIDs.append(assetID)
        }
        undoHistory.append(assetID)
        currentPosition += 1
        updatedAt = Date()
    }

    @discardableResult
    mutating func undoLastDecision() -> String? {
        guard let assetID = undoHistory.popLast(),
              let assetIndex = orderedAssetIDs.firstIndex(of: assetID) else {
            return nil
        }

        decisions.removeValue(forKey: assetID)
        pendingDeletionIDs.removeAll { $0 == assetID }
        currentPosition = assetIndex
        updatedAt = Date()
        return assetID
    }

    mutating func skipUnavailableAsset(id assetID: String) {
        guard let assetIndex = orderedAssetIDs.firstIndex(of: assetID) else {
            return
        }

        if !unavailableAssetIDs.contains(assetID) {
            unavailableAssetIDs.append(assetID)
        }
        if assetIndex == currentPosition {
            currentPosition += 1
        }
        updatedAt = Date()
    }
}
