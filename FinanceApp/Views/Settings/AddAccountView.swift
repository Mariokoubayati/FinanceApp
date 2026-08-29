import SwiftUI

struct AddAccountView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    var onCreate: (Account) -> Void

    @State private var name          = ""
    @State private var type          = Account.AccountType.bank
    @State private var balanceText   = "0"
    @State private var selectedColor = "#5B8DEF"
    @State private var isLoading     = false
    @State private var errorMessage: String?

    private let colors = [
        "#5B8DEF", "#34C759", "#FF6B6B", "#FFD60A",
        "#BF5AF2", "#FF9F0A", "#FF453A", "#64D2FF"
    ]

    var isValid: Bool {
        !name.isEmpty && Double(balanceText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Account Name (e.g. Chase Checking)", text: $name)

                    Picker("Type", selection: $type) {
                        ForEach(Account.AccountType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }

                    HStack {
                        Text("Starting Balance ($)").foregroundStyle(.secondary)
                        Spacer()
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(!isValid || isLoading)
                }
            }
        }
    }

    private func save() async {
        guard let uid = appState.userId,
              let balance = Double(balanceText) else { return }
        isLoading = true
        errorMessage = nil
        do {
            let insert = AccountInsert(
                userId: uid, name: name, type: type.rawValue,
                balance: balance, currency: "USD", color: selectedColor
            )
            let account = try await AccountService.shared.create(insert)
            onCreate(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
