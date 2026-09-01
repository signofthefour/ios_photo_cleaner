import Observation

@MainActor
@Observable
final class AlbumPickerViewModel {
    enum State: Equatable {
        case loading
        case content(albums: [PhotoAlbum])
        case empty
        case failed(message: String)
    }

    private let assetID: String
    private let library: any PhotoLibraryServiceProtocol

    private(set) var state: State = .loading
    private(set) var membershipAlbumIDs: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var isCreatingAlbum = false
    private(set) var createAlbumErrorMessage: String?
    var searchText = ""

    init(assetID: String, library: any PhotoLibraryServiceProtocol) {
        self.assetID = assetID
        self.library = library
    }

    var filteredAlbums: [PhotoAlbum] {
        guard case let .content(albums) = state else { return [] }
        guard !searchText.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func isMember(of album: PhotoAlbum) -> Bool {
        membershipAlbumIDs.contains(album.id)
    }

    func load() async {
        state = .loading
        do {
            async let albums = library.fetchAlbums()
            async let membership = library.albumIDs(containingAssetID: assetID)
            let (fetchedAlbums, fetchedMembership) = try await (albums, membership)
            membershipAlbumIDs = fetchedMembership
            state = fetchedAlbums.isEmpty ? .empty : .content(albums: fetchedAlbums)
        } catch {
            state = .failed(message: "Albums could not be loaded. Please try again.")
        }
    }

    /// Marks `album` as containing the asset immediately, then confirms
    /// with a real add request; a failure rolls the checkmark back. A
    /// repeat tap on an album the asset already belongs to is a no-op —
    /// adding never toggles membership off.
    func add(to album: PhotoAlbum) async {
        guard !isMember(of: album) else { return }
        membershipAlbumIDs.insert(album.id)
        errorMessage = nil
        do {
            try await library.addAsset(assetID, toAlbum: album.id)
        } catch {
            membershipAlbumIDs.remove(album.id)
            errorMessage = "Could not add this photo to \"\(album.title)\". Please try again."
        }
    }

    /// Creates the album, inserts it into the loaded list, and immediately
    /// adds the current asset to it — this screen exists to add the
    /// current photo somewhere, so creating an album without adding the
    /// photo to it would need a redundant second tap.
    func createAlbum(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCreatingAlbum = true
        createAlbumErrorMessage = nil
        defer { isCreatingAlbum = false }

        do {
            let album = try await library.createAlbum(named: trimmed)
            var albums = state.albums ?? []
            albums.append(album)
            albums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            state = .content(albums: albums)
            await add(to: album)
        } catch {
            createAlbumErrorMessage = "This album could not be created. Please try again."
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissCreateAlbumError() {
        createAlbumErrorMessage = nil
    }
}

private extension AlbumPickerViewModel.State {
    var albums: [PhotoAlbum]? {
        if case let .content(albums) = self { albums } else { nil }
    }
}
