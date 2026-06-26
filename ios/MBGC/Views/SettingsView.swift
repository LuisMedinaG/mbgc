import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    } label: {
                        SettingsRow(icon: "paintbrush.fill", color: .purple, label: "Appearance")
                    }
                    .pickerStyle(.menu)
                }

                Section("Import") {
                    NavigationLink { ImportView(dismissAll: { isPresented = false }) } label: {
                        SettingsRow(icon: "arrow.down.circle.fill", color: .orange, label: "Import from BGG")
                    }
                    NavigationLink { CsvImportView() } label: {
                        SettingsRow(icon: "doc.text.fill", color: .green, label: "Import from CSV")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}
