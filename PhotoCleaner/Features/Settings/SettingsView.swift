import SwiftUI

@MainActor
struct SettingsView: View {
    @State private var model: SettingsViewModel

    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Form {
            Section("Photo Library") {
                LabeledContent("Access", value: model.accessLabel)
                Text("Milestone 1 uses safe mock photos and never requests access to your real library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .task { await model.load() }
    }
}
