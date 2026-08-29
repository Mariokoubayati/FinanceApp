import SwiftUI

struct SignUpView: View {
    @Environment(AppState.self) var appState

    @State private var fullName        = ""
    @State private var email           = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var isLoading    = false
    @State private var errorMessage: String?

    var allFilled: Bool {
        !fullName.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TextField("Full Name", text: $fullName)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))

                SecureField("Password (min 6 characters)", text: $password)
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))

                SecureField("Confirm Password", text: $confirmPassword)
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button { Task { await signUp() } } label: {
                    ZStack {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text("Create Account").font(.headline) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(allFilled ? Color.blue : Color.blue.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(isLoading || !allFilled)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() async {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(fullName)]
            )
            // If email confirmation is disabled, a session is returned immediately
            let s = try await supabase.auth.session
            appState.session = s
            await appState.loadProfile(userId: s.user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
