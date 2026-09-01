import SwiftData

@MainActor
final class AppContainer {
    let library: any PhotoLibraryServiceProtocol
    let sessions: any SessionRepositoryProtocol

    init(
        library: any PhotoLibraryServiceProtocol,
        sessions: any SessionRepositoryProtocol
    ) {
        self.library = library
        self.sessions = sessions
    }

    static var liveMock: AppContainer {
        AppContainer(
            library: MockPhotoLibraryService.sample,
            sessions: InMemorySessionRepository()
        )
    }

    private static let sessionModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: PersistedCleaningSession.self)
        } catch {
            fatalError("Failed to create session ModelContainer: \(error)")
        }
    }()

    /// Backed by the real photo library via PhotoKit, with sessions
    /// durably persisted via SwiftData so a saved session survives an
    /// app relaunch.
    static var live: AppContainer {
        AppContainer(
            library: PhotoKitPhotoLibraryService(),
            sessions: SwiftDataSessionRepository(modelContainer: sessionModelContainer)
        )
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(library: library, sessions: sessions)
    }

    func makeSourcePickerViewModel() -> SourcePickerViewModel {
        SourcePickerViewModel(library: library)
    }

    func makeCleanerViewModel(source: CleaningSource) -> CleanerViewModel {
        CleanerViewModel(source: source, library: library, sessions: sessions)
    }

    func makeDeletionReviewViewModel() -> DeletionReviewViewModel {
        DeletionReviewViewModel(library: library, sessions: sessions)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(library: library)
    }
}
