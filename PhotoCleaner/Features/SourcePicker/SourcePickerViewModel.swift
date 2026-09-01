import Observation

@MainActor
@Observable
final class SourcePickerViewModel {
    enum State: Equatable {
        case loading
        case content(timeline: [TimelineGroup], albums: [PhotoAlbum])
        case empty
        case failed(message: String)
    }

    private let library: any PhotoLibraryServiceProtocol
    private(set) var state: State = .loading

    init(library: any PhotoLibraryServiceProtocol) {
        self.library = library
    }

    var libraryChanges: AsyncStream<Void> { library.libraryChanges }

    func load() async {
        state = .loading
        await refresh()
    }

    /// Re-fetches sources without showing the loading state, so a library
    /// change while this screen is open updates counts in place instead of
    /// flashing a spinner over already-visible content. A failed refresh is
    /// silently ignored — whatever was already on screen stays valid.
    func refreshIfNeeded() async {
        guard case .content = state else { return }
        async let timeline = library.fetchTimelineGroups()
        async let albums = library.fetchAlbums()
        guard let (loadedTimeline, loadedAlbums) = try? await (timeline, albums) else { return }
        state = loadedTimeline.isEmpty && loadedAlbums.isEmpty
            ? .empty
            : .content(timeline: loadedTimeline, albums: loadedAlbums)
    }

    private func refresh() async {
        do {
            async let timeline = library.fetchTimelineGroups()
            async let albums = library.fetchAlbums()
            let (loadedTimeline, loadedAlbums) = try await (timeline, albums)
            state = loadedTimeline.isEmpty && loadedAlbums.isEmpty
                ? .empty
                : .content(timeline: loadedTimeline, albums: loadedAlbums)
        } catch {
            state = .failed(message: "Photo sources could not be loaded. Please try again.")
        }
    }

    func photoCount(for source: CleaningSource) -> Int {
        switch source {
        case let .timeline(group): group.photoCount
        case let .album(album): album.photoCount
        case .random: 0
        }
    }
}
