import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email or username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                if let error = auth.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Button("Log In") {
                    Task { await auth.login(username: username, password: password) }
                }
                .disabled(username.isEmpty || password.isEmpty || auth.isLoading)
            }
            .navigationTitle("MBGC")
        }
    }
}
