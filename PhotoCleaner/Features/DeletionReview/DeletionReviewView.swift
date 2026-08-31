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
                        .font(.callout).padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.pendingIDs, id: \.self) { id in
                            VStack {
                                Image(systemName: "photo").font(.largeTitle)
                                Text(id).font(.caption).lineLimit(2)
                                Button("Restore") { Task { try? await model.restore(id: id) } }
                            }
                            .padding().frame(maxWidth: .infinity)
                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(model.selectedIDs.contains(id) ? "Selected" : "Not selected")
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("Pending Deletion")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Select All") { model.selectAll() }
                Button("Deselect All") { model.deselectAll() }
                Spacer()
                Button("Cancel") { model.cancel(); dismiss() }
                Button("Confirm (Mock)") { model.confirmMockDeletion() }
                    .disabled(model.selectedIDs.isEmpty)
            }
        }
        .alert("Safe Mock", isPresented: Binding(
            get: { model.confirmationMessage != nil },
            set: { if !$0 { model.dismissConfirmation() } }
        )) { Button("OK") {} } message: { Text(model.confirmationMessage ?? "") }
        .task { await model.load() }
    }
}
