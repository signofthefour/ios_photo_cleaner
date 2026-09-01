import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let library: any PhotoLibraryServiceProtocol
    private(set) var accessStatus: PhotoAccessStatus = .notDetermined

    init(library: any PhotoLibraryServiceProtocol) {
        self.library = library
    }

    func load() async {
        accessStatus = await library.requestAuthorization()
    }

    var accessLabel: String {
        switch accessStatus {
        case .notDetermined: "Not Requested"
        case .limited: "Limited Photo Access"
        case .authorized: "Full Photo Access"
        case .denied: "Photo Access Denied"
        case .restricted: "Photo Access Restricted"
        }
    }

    /// Only `.denied` is user-recoverable from the Settings app; `.restricted`
    /// is enforced externally (parental controls, MDM) and a Settings link
    /// would not actually let the user change anything.
    var canRecoverAccessInSettings: Bool {
        accessStatus == .denied
    }
}
