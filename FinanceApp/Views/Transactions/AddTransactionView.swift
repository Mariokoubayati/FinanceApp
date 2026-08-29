import SwiftUI

struct AddTransactionView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    var vm: TransactionsViewModel

    // Unified mode: Expense / Income / Transfer
    enum AddMode: String, CaseIterable {
        case expense  = "Expense"
        case income   = "Income"
        case transfer = "Transfer"
    }

    @State private var addMode           = AddMode.expense
    @State private var amountText        = ""
    @State private var descriptionText   = ""
    @State private var noteText          = ""
    @State private var selectedAccountId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var date              = Date()
    @State private var isLoading         = false

    // Transfer-specific
    @State private var transferFromId: UUID?
    @State private var transferToId:   UUID?

    // MARK: - Derived

    var currentCategories: [Category] {
        switch addMode {
        case .expense:  return vm.categories.filter { $0.type == .expense }
        case .income:   return vm.categories.filter { $0.type == .income  }
        case .transfer: return []
        }
    }

    var isValid: Bool {
        guard let v = Double(amountText), v > 0 else { return false }
        switch addMode {
        case .expense, .income:
            return !descriptionText.isEmpty && selectedAccountId != nil
        case .transfer:
            guard let from = transferFromId, let to = transferToId else { return false }
            return from != to
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Mode picker
                Section {
                    Picker("Mode", selection: $addMode) {
                        ForEach(AddMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: addMode) { _, _ in selectedCategoryId = nil }
                }

                // Amount — always visible
                Section("Amount") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$").foregroundStyle(.secondary).font(.title2)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                    }
                }

                if addMode == .transfer {
                    transferSections
                } else {
                    transactionSections
                }
            }
            .navigationTitle(addMode == .transfer ? "Transfer" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isLoading)
                }
            }
        }
        .onAppear {
            selectedAccountId = vm.accounts.first?.id
            transferFromId    = vm.accounts.first?.id
            transferToId      = vm.accounts.count > 1 ? vm.accounts[1].id : nil
            selectedCategoryId = currentCategories.first?.id
        }
    }

    // MARK: - Transfer form

    @ViewBuilder
    private var transferSections: some View {
        if vm.accounts.count < 2 {
            Section {
                Label("You need at least 2 accounts to make a transfer.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            }
        }

        Section("Date & Note") {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Note (optional)", text: $noteText)
        }

        Section("From Account") {
            if vm.accounts.isEmpty {
                Text("Add accounts in Settings first")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(vm.accounts) { acc in
                    accountRow(acc, selectedId: $transferFromId)
                        .opacity(acc.id == transferToId ? 0.35 : 1)
                        .disabled(acc.id == transferToId)
                }
            }
        }

        Section("To Account") {
            if vm.accounts.isEmpty {
                Text("Add accounts in Settings first")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(vm.accounts) { acc in
                    accountRow(acc, selectedId: $transferToId)
                        .opacity(acc.id == transferFromId ? 0.35 : 1)
                        .disabled(acc.id == transferFromId)
                }
            }
        }
    }

    // MARK: - Transaction form

    @ViewBuilder
    private var transactionSections: some View {
        Section("Details") {
            TextField("Description", text: $descriptionText)
            TextField("Note (optional)", text: $noteText)
            DatePicker("Date", selection: $date, displayedComponents: .date)
        }

        Section("Account") {
            if vm.accounts.isEmpty {
                Text("Add an account in Settings first")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(vm.accounts) { acc in
                    accountRow(acc, selectedId: $selectedAccountId)
                }
            }
        }

        if !currentCategories.isEmpty {
            Section("Category") {
                ForEach(currentCategories) { cat in
                    categoryRow(cat)
                }
            }
        }
    }

    // MARK: - Row helpers

    private func accountRow(_ acc: Account, selectedId: Binding<UUID?>) -> some View {
        HStack {
            Image(systemName: acc.type.icon)
                .foregroundStyle(Color(hex: acc.color))
                .frame(width: 28)
            Text(acc.name)
            Spacer()
            if selectedId.wrappedValue == acc.id {
                Image(systemName: "checkmark").foregroundStyle(.blue)
            }
        }
        .contentShape(.rect)
        .onTapGesture { selectedId.wrappedValue = acc.id }
    }

    private func categoryRow(_ cat: Category) -> some View {
        HStack {
            Image(systemName: cat.icon)
                .foregroundStyle(Color(hex: cat.color))
                .frame(width: 28)
            Text(cat.name)
            Spacer()
            if selectedCategoryId == cat.id {
                Image(systemName: "checkmark").foregroundStyle(.blue)
            }
        }
        .contentShape(.rect)
        .onTapGesture { selectedCategoryId = cat.id }
    }

    // MARK: - Save

    private func save() async {
        guard let uid = appState.userId,
              let amount = Double(amountText) else { return }
        isLoading = true

        if addMode == .transfer {
            guard let from = transferFromId, let to = transferToId else {
                isLoading = false; return
            }
            await vm.transfer(
                userId: uid,
                fromAccountId: from,
                toAccountId: to,
                amount: amount,
                note: noteText.isEmpty ? nil : noteText,
                date: date
            )
        } else {
            guard let accId = selectedAccountId else { isLoading = false; return }
            let txType: Transaction.TransactionType = addMode == .income ? .income : .expense
            await vm.add(
                userId: uid,
                accountId: accId,
                categoryId: selectedCategoryId,
                type: txType,
                amount: amount,
                description: descriptionText,
                note: noteText.isEmpty ? nil : noteText,
                date: date
            )
        }

        isLoading = false
        dismiss()
    }
}
