import SwiftUI

struct TransactionDetailView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    let transaction: Transaction
    var vm: TransactionsViewModel

    @State private var isEditing  = false
    @State private var isSaving   = false

    // Edit-mode states
    @State private var editType:        Transaction.TransactionType = .expense
    @State private var editAmountText   = ""
    @State private var editDescription  = ""
    @State private var editNote         = ""
    @State private var editDate         = Date()
    @State private var editCategoryId:  UUID?

    // MARK: - Derived

    private var category: Category? { vm.category(for: transaction.categoryId) }
    private var account:  Account?  { vm.account(for: transaction.accountId) }

    private var editCategories: [Category] {
        vm.categories.filter { $0.type.rawValue == editType.rawValue }
    }

    private var editIsValid: Bool {
        guard let v = Double(editAmountText), v > 0 else { return false }
        return !editDescription.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isEditing { editForm } else { detailView }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") { isEditing = false }
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Save") { Task { await saveEdits() } }
                            .disabled(!editIsValid || isSaving)
                    } else {
                        Button { populateEditFields(); isEditing = true } label: {
                            Image(systemName: "pencil")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detail (read-only)

    private var detailView: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Hero block
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: category?.color ?? "#8E8E93").opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: category?.icon ?? "creditcard.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color(hex: category?.color ?? "#8E8E93"))
                    }
                    Text((transaction.type == .income ? "+" : "–") +
                         transaction.amount.formatted(.currency(code: "USD")))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(transaction.type == .income ? .green : .primary)
                    if let cat = category {
                        Text(cat.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                // Info rows
                VStack(spacing: 0) {
                    infoRow(icon: "text.alignleft",
                            label: "Description",
                            value: transaction.description)
                    Divider().padding(.leading, 52)
                    infoRow(icon: "calendar",
                            label: "Date",
                            value: transaction.dateValue.formatted(date: .long, time: .omitted))
                    Divider().padding(.leading, 52)
                    infoRow(icon: account?.type.icon ?? "creditcard.fill",
                            label: "Account",
                            value: account?.name ?? "—")
                    Divider().padding(.leading, 52)
                    infoRow(icon: transaction.type == .income ? "arrow.down.circle" : "arrow.up.circle",
                            label: "Type",
                            value: transaction.type == .income ? "Income" : "Expense")
                    if let note = transaction.note, !note.isEmpty {
                        Divider().padding(.leading, 52)
                        infoRow(icon: "note.text", label: "Note", value: note)
                    }
                }
                .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Edit form

    private var editForm: some View {
        Form {
            Section {
                Picker("Type", selection: $editType) {
                    Text("Expense").tag(Transaction.TransactionType.expense)
                    Text("Income") .tag(Transaction.TransactionType.income)
                }
                .pickerStyle(.segmented)
                .onChange(of: editType) { _, _ in editCategoryId = nil }
            }

            Section("Amount") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$").foregroundStyle(.secondary).font(.title2)
                    TextField("0.00", text: $editAmountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.bold())
                }
            }

            Section("Details") {
                TextField("Description", text: $editDescription)
                TextField("Note (optional)", text: $editNote)
                DatePicker("Date", selection: $editDate, displayedComponents: .date)
            }

            if !editCategories.isEmpty {
                Section("Category") {
                    ForEach(editCategories) { cat in
                        HStack {
                            Image(systemName: cat.icon)
                                .foregroundStyle(Color(hex: cat.color))
                                .frame(width: 28)
                            Text(cat.name)
                            Spacer()
                            if editCategoryId == cat.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture { editCategoryId = cat.id }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func populateEditFields() {
        editType        = transaction.type
        editAmountText  = String(format: "%.2f", transaction.amount)
        editDescription = transaction.description
        editNote        = transaction.note ?? ""
        editDate        = transaction.dateValue
        editCategoryId  = transaction.categoryId
    }

    private func saveEdits() async {
        guard let amount = Double(editAmountText) else { return }
        isSaving = true
        await vm.update(
            transaction:  transaction,
            categoryId:   editCategoryId,
            type:         editType,
            amount:       amount,
            description:  editDescription,
            note:         editNote.isEmpty ? nil : editNote,
            date:         editDate
        )
        isSaving  = false
        isEditing = false
        dismiss()
    }
}
