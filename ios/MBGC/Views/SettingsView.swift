import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showImportBGG = false

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
                    Button { showImportBGG = true } label: {
                        SettingsRow(icon: "arrow.down.circle.fill", color: .orange, label: "Import from BGG")
                    }
                    .foregroundStyle(.primary)
                    NavigationLink { CsvImportView() } label: {
                        SettingsRow(icon: "doc.text.fill", color: .green, label: "Import from CSV")
                    }
                }

                Section("Help") {
                    // Resets the gate flag; ContentView's fullScreenCover reopens on dismiss.
                    Button { hasSeenOnboarding = false; isPresented = false } label: {
                        SettingsRow(icon: "sparkles", color: .blue, label: "Restart Intro")
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showImportBGG) {
            ImportView(dismissAll: { showImportBGG = false; isPresented = false })
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
