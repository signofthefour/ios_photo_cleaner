import SwiftUI

@MainActor
struct SettingsView: View {
    @State private var model: SettingsViewModel
    @Environment(\.openURL) private var openURL

    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Form {
            Section("Photo Library") {
                LabeledContent("Access", value: model.accessLabel)
                Text("Full or limited access lets Photo Cleaner browse your photos. Permanent deletion always requires a separate confirmation, both in this app and from iOS itself.")
                    .font(.footnote).foregroundStyle(.secondary)

                if model.canRecoverAccessInSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task { await model.load() }
    }
}
