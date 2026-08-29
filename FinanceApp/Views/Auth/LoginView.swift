import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) var appState

    @State private var email    = ""
    @State private var password = ""
    @State private var isLoading    = false
    @State private var errorMessage: String?
    @State private var showSignUp   = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue.gradient)
                    Text("FinanceTracker")
                        .font(.largeTitle.bold())
                    Text("Track income, savings & payments")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Form
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(.secondary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .padding()
                        .background(.secondary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button { Task { await signIn() } } label: {
                        ZStack {
                            if isLoading { ProgressView().tint(.white) }
                            else { Text("Sign In").font(.headline) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(email.isEmpty || password.isEmpty ? Color.blue.opacity(0.4) : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()

                Button { showSignUp = true } label: {
                    HStack(spacing: 4) {
                        Text("Don't have an account?").foregroundStyle(.secondary)
                        Text("Sign Up").fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .padding(.bottom, 44)
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await supabase.auth.signIn(email: email, password: password)
            let s = try await supabase.auth.session
            appState.session = s
            await appState.loadProfile(userId: s.user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
