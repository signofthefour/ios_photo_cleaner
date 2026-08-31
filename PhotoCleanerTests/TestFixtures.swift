import Foundation
@testable import PhotoCleaner

extension CleaningSession {
    static func fixture(assetIDs: [String]) -> CleaningSession {
        CleaningSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            source: .album(PhotoAlbum(id: "album", title: "Mock Album", photoCount: assetIDs.count)),
            orderedAssetIDs: assetIDs,
            currentPosition: 0,
            decisions: [:],
            pendingDeletionIDs: [],
            unavailableAssetIDs: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func fixturePendingDeletion(ids: [String]) -> CleaningSession {
        var session = fixture(assetIDs: ids)
        for id in ids {
            try! session.decide(.pendingDelete, assetID: id)
        }
        return session
    }
}
