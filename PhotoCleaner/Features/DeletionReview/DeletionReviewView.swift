import SwiftUI

@MainActor
struct DeletionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeletionReviewViewModel
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(model: DeletionReviewViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading Queue")
            } else if let error = model.errorMessage {
                ContentUnavailableView("Could Not Load Queue", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.pendingIDs.isEmpty {
                ContentUnavailableView("Queue Is Empty", systemImage: "trash.slash", description: Text("No photos are pending deletion."))
            } else {
                ScrollView {
                    Text("Review every identifier below before any future deletion request.")
                        .font(.callout)
                        .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                        .padding(.horizontal)
                        .padding(.top, PhotoCleanerTheme.spacing)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.pendingIDs, id: \.self) { id in
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(PhotoCleanerTheme.Palette.line)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            Image(systemName: "photo")
                                                .font(.title2)
                                                .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                                        }

                                    if model.selectedIDs.contains(id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.callout)
                                            .foregroundStyle(.white, PhotoCleanerTheme.Palette.ink)
                                            .padding(6)
                                    }
                                }

                                Text(id)
                                    .font(.caption2)
                                    .foregroundStyle(PhotoCleanerTheme.Palette.inkSoft)
                                    .lineLimit(1)

                                Button("Restore") { Task { try? await model.restore(id: id) } }
                                    .font(.caption)
                            }
                            .padding(10)
                            .background(PhotoCleanerTheme.Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: PhotoCleanerTheme.rowCornerRadius)
                                    .stroke(PhotoCleanerTheme.Palette.line, lineWidth: 1)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(model.selectedIDs.contains(id) ? "Selected" : "Not selected")
                        }
                    }.padding()
                }
            }
        }
        .background(PhotoCleanerTheme.Palette.background)
        .navigationTitle("Pending Deletion")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Select All") { model.selectAll() }
                Button("Deselect All") { model.deselectAll() }
                Spacer()
                Button("Cancel") { model.cancel(); dismiss() }
                    .tint(PhotoCleanerTheme.Palette.inkSoft)
                Button("Confirm (Mock)") { model.confirmMockDeletion() }
                    .disabled(model.selectedIDs.isEmpty)
                    .tint(PhotoCleanerTheme.Palette.delete)
            }
        }
        .alert("Safe Mock", isPresented: Binding(
            get: { model.confirmationMessage != nil },
            set: { if !$0 { model.dismissConfirmation() } }
        )) { Button("OK") {} } message: { Text(model.confirmationMessage ?? "") }
        .task { await model.load() }
    }
}
