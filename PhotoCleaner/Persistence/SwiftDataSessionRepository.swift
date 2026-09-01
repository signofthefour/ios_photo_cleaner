import Foundation
import SwiftData

@ModelActor
actor SwiftDataSessionRepository: SessionRepositoryProtocol {
    func loadCurrent() async throws -> CleaningSession? {
        var descriptor = FetchDescriptor<PersistedCleaningSession>()
        descriptor.fetchLimit = 1
        guard let stored = try modelContext.fetch(descriptor).first else { return nil }
        return try JSONDecoder().decode(CleaningSession.self, from: stored.payload)
    }

    func save(_ session: CleaningSession) async throws {
        try await removeCurrent()
        modelContext.insert(PersistedCleaningSession(payload: try JSONEncoder().encode(session)))
        try modelContext.save()
    }

    func removeCurrent() async throws {
        for stored in try modelContext.fetch(FetchDescriptor<PersistedCleaningSession>()) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }
}
