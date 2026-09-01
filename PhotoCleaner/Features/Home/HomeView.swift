import SwiftUI

@MainActor
struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(\.openURL) private var openURL
    let onNavigate: (AppRoute) -> Void

    init(model: HomeViewModel, onNavigate: @escaping (AppRoute) -> Void) {
        _model = State(initialValue: model)
        self.onNavigate = onNavigate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhotoCleanerTheme.spacing) {
                header

                if let errorMessage = model.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                        Button("Retry") {
                            Task { await model.load() }
                        }
                    }
                    .rowStyle()
                }

                if model.accessStatus == .denied || model.accessStatus == .restricted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            model.accessStatus == .denied
                                ? "Photo access is turned off, so there's nothing to clean yet."
                                : "Photo access is restricted on this device."
                        )
                        .font(.footnote)
                        .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)

                        if model.accessStatus == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                    .rowStyle()
                }

                if let savedSession = model.savedSession {
                    Button {
                        onNavigate(.cleaner(savedSession.source))
                    } label: {
                        HStack(spacing: PhotoCleanerTheme.spacing) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Continue Cleaning")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(savedSession.pendingDeletionIDs.count) pending deletion")
                                    .font(.caption)
                                    .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                            chevron
                        }
                    }
                    .accessibilityHint("Resumes your saved cleaning session")
                    .buttonStyle(.plain)
                    .rowStyle()
                }

                HStack(spacing: PhotoCleanerTheme.spacing) {
                    actionTile(
                        title: "Clean by Month",
                        systemImage: "calendar",
                        action: { onNavigate(.sourcePicker) },
                        hint: "Choose a month to review"
                    )
                    actionTile(
                        title: "Clean an Album",
                        systemImage: "rectangle.stack",
                        action: { onNavigate(.sourcePicker) },
                        hint: "Choose an album to review"
                    )
                }

                Button {
                    onNavigate(.cleaner(.random))
                } label: {
                    HStack(spacing: PhotoCleanerTheme.spacing) {
                        ZStack {
                            Circle().fill(PhotoCleanerTheme.Palette.background)
                            Image(systemName: "shuffle")
                                .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Give Me Random")
                                .font(.subheadline.weight(.semibold))
                            Text("Photos pop up in random order from your whole library")
                                .font(.caption)
                                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                        }

                        Spacer(minLength: 0)
                        chevron
                    }
                    .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                }
                .accessibilityHint("Starts a review of your whole library in random order")
                .buttonStyle(.plain)
                .rowStyle()

                Button {
                    onNavigate(.deletionReview)
                } label: {
                    HStack(spacing: PhotoCleanerTheme.spacing) {
                        ZStack {
                            Circle().fill(PhotoCleanerTheme.Palette.deleteSoft)
                            Image(systemName: "trash")
                                .foregroundStyle(PhotoCleanerTheme.Palette.delete)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pending Deletion")
                                .font(.subheadline.weight(.semibold))
                            Text("Review before anything is removed")
                                .font(.caption)
                                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                        }

                        Spacer(minLength: 0)

                        Text("\(model.pendingDeletionCount)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(PhotoCleanerTheme.Palette.surface)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PhotoCleanerTheme.Palette.ink, in: Capsule())

                        chevron
                    }
                    .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                }
                .accessibilityHint("Shows every photo currently queued for deletion")
                .buttonStyle(.plain)
                .rowStyle()

                Button("Settings") {
                    onNavigate(.settings)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(PhotoCleanerTheme.spacing)
        }
        .background(PhotoCleanerTheme.Palette.background)
        .navigationTitle("Photo Cleaner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if model.isLoading {
                ProgressView("Loading")
            }
        }
        .task {
            await model.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Photo Cleaner")
                .font(.largeTitle.bold())
            LabeledContent("Access", value: accessLabel)
                .font(.footnote)
                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
    }

    private func actionTile(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        hint: String
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PhotoCleanerTheme.Palette.ink)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHint(hint)
        .buttonStyle(.plain)
        .rowStyle()
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

private struct RowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(PhotoCleanerTheme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius)
                    .stroke(PhotoCleanerTheme.Palette.line, lineWidth: 1)
            }
    }
}

private extension View {
    func rowStyle() -> some View {
        modifier(RowStyle())
    }
}
