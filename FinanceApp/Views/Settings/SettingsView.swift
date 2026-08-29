import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @State private var accounts: [Account] = []
    @State private var showAddAccount = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile section
                Section("Profile") {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .purple],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Text(initials).font(.title3.bold()).foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.profile?.fullName ?? "User").font(.headline)
                            Text(appState.session?.user.email ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Accounts section
                Section {
                    ForEach(accounts) { account in
                        HStack {
                            Image(systemName: account.type.icon)
                                .foregroundStyle(Color(hex: account.color))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text(account.type.displayName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(account.balance.formatted(.currency(code: account.currency)))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        Task {
                            for i in offsets {
                                try? await AccountService.shared.softDelete(id: accounts[i].id)
                            }
                            accounts.remove(atOffsets: offsets)
                        }
                    }

                    Button { showAddAccount = true } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                } header: {
                    Text("Accounts")
                }

                // App info
                Section("App") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        Task { await appState.signOut() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddAccount) {
                AddAccountView { newAccount in
                    accounts.append(newAccount)
                }
                .environment(appState)
            }
            .task {
                if let uid = appState.userId {
                    accounts = (try? await AccountService.shared.fetchAll(userId: uid)) ?? []
                }
            }
        }
    }

    private var initials: String {
        let parts = (appState.profile?.fullName ?? "").split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String((appState.profile?.fullName ?? "U").prefix(2)).uppercased()
    }
}
