import SwiftUI

struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        Form {
            Section("BoardGameGeek") {
                TextField("BGG Username", text: $viewModel.bggInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
                if let success = viewModel.successMessage {
                    Text(success).foregroundStyle(.green).font(.caption)
                }
                Button("Save") {
                    viewModel.saveBGG()
                }
                .disabled(
                    viewModel.isSaving ||
                    viewModel.bggInput.trimmingCharacters(in: .whitespaces).isEmpty ||
                    viewModel.bggInput.trimmingCharacters(in: .whitespaces) == viewModel.bggUsername
                )
            }
        }
        .navigationTitle("Profile")
        .task { await viewModel.load() }
    }
}
