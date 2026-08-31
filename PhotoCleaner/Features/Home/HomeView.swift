import SwiftUI

@MainActor
struct HomeView: View {
    @State private var model: HomeViewModel
    let onNavigate: (AppRoute) -> Void

    init(model: HomeViewModel, onNavigate: @escaping (AppRoute) -> Void) {
        _model = State(initialValue: model)
        self.onNavigate = onNavigate
    }

    var body: some View {
        List {
            Section("Photo Access") {
                LabeledContent("Status", value: accessLabel)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                    Button("Retry") {
                        Task { await model.load() }
                    }
                }
            }

            Section("Clean Photos") {
                if let savedSession = model.savedSession {
                    Button("Continue Cleaning") {
                        onNavigate(.cleaner(savedSession.source))
                    }
                    .accessibilityHint("Resumes your saved cleaning session")
                }

                Button("Clean by Date") {
                    onNavigate(.sourcePicker)
                }
                .accessibilityHint("Choose a timeline group to review")

                Button("Clean an Album") {
                    onNavigate(.sourcePicker)
                }
                .accessibilityHint("Choose an album to review")
            }

            Section {
                Button("Pending Deletion Review (\(model.pendingDeletionCount))") {
                    onNavigate(.deletionReview)
                }
                .accessibilityHint("Shows every photo currently queued for deletion")

                Button("Settings") {
                    onNavigate(.settings)
                }
            }
        }
        .navigationTitle("Photo Cleaner")
        .overlay {
            if model.isLoading {
                ProgressView("Loading")
            }
        }
        .task {
            await model.load()
        }
    }

    private var accessLabel: String {
        switch model.accessStatus {
        case .notDetermined: "Not Requested"
        case .limited: "Limited Access"
        case .authorized: "Full Access"
        case .denied: "Access Denied"
        case .restricted: "Access Restricted"
        }
    }
}
