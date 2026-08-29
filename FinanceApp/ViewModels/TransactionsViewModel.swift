import SwiftUI

@Observable
@MainActor
final class TransactionsViewModel {
    var transactions: [Transaction] = []
    var accounts:     [Account]     = []
    var categories:   [Category]    = []
    var isLoading    = false
    var errorMessage: String?
    var filterType: FilterType = .all

    // Search & category filter
    var searchText:       String  = ""
    var filterCategoryId: UUID?   = nil

    // Month navigation
    var selectedYear:  Int = Calendar.current.component(.year,  from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    enum FilterType: String, CaseIterable {
        case all = "All", income = "Income", expense = "Expense"
    }

    // MARK: - Month helpers

    var monthYearTitle: String {
        var comps = DateComponents()
        comps.year  = selectedYear
        comps.month = selectedMonth
        comps.day   = 1
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    func goToPreviousMonth() {
        if selectedMonth == 1 { selectedMonth = 12; selectedYear -= 1 }
        else { selectedMonth -= 1 }
    }

    func goToNextMonth() {
        if selectedMonth == 12 { selectedMonth = 1; selectedYear += 1 }
        else { selectedMonth += 1 }
    }

    private func isInSelectedMonth(_ tx: Transaction) -> Bool {
        let comps = Calendar.current.dateComponents([.year, .month], from: tx.dateValue)
        return comps.year == selectedYear && comps.month == selectedMonth
    }

    // MARK: - Category chips

    var visibleCategoryChips: [Category] {
        switch filterType {
        case .income:  return categories.filter { $0.type == .income  }
        case .expense: return categories.filter { $0.type == .expense }
        case .all:     return categories
        }
    }

    // MARK: - Filtered list (month + type + category + search)

    var filtered: [Transaction] {
        var result = transactions.filter { isInSelectedMonth($0) }

        switch filterType {
        case .income:  result = result.filter { $0.type == .income  }
        case .expense: result = result.filter { $0.type == .expense }
        case .all:     break
        }

        if let catId = filterCategoryId {
            result = result.filter { $0.categoryId == catId }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.description.lowercased().contains(q) ||
                ($0.note?.lowercased().contains(q) ?? false)
            }
        }

        return result
    }

    // MARK: - Monthly totals

    var monthlyIncome: Double {
        transactions
            .filter { isInSelectedMonth($0) && $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    var monthlyExpense: Double {
        transactions
            .filter { isInSelectedMonth($0) && $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Load

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        async let txnsTask = TransactionService.shared.fetchAll(userId: userId)
        async let accsTask = AccountService.shared.fetchAll(userId: userId)
        async let catsTask = TransactionService.shared.fetchCategories()
        do {
            (transactions, accounts, categories) = try await (txnsTask, accsTask, catsTask)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Add transaction

    func add(
        userId: UUID,
        accountId: UUID,
        categoryId: UUID?,
        type: Transaction.TransactionType,
        amount: Double,
        description: String,
        note: String?,
        date: Date
    ) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let insert = TransactionInsert(
            userId: userId,
            accountId: accountId,
            categoryId: categoryId,
            type: type.rawValue,
            amount: amount,
            description: description,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            date: f.string(from: date)
        )
        do {
            let newTx = try await TransactionService.shared.insert(insert)
            transactions.insert(newTx, at: 0)
            let delta = type == .income ? amount : -amount
            if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
                let updated = accounts[idx].balance + delta
                accounts[idx].balance = updated
                try await AccountService.shared.updateBalance(accountId: accountId, newBalance: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit transaction

    func update(
        transaction: Transaction,
        categoryId: UUID?,
        type: Transaction.TransactionType,
        amount: Double,
        description: String,
        note: String?,
        date: Date
    ) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let payload = TransactionUpdate(
            categoryId: categoryId,
            type: type.rawValue,
            amount: amount,
            description: description,
            note: note.flatMap { $0.isEmpty ? nil : $0 },
            date: f.string(from: date)
        )
        do {
            let updated = try await TransactionService.shared.update(id: transaction.id, payload)
            if let idx = transactions.firstIndex(where: { $0.id == transaction.id }) {
                transactions[idx] = updated
            }
            // Adjust account balance: revert old, apply new
            let oldDelta = transaction.type == .income ? -transaction.amount :  transaction.amount
            let newDelta = type            == .income ?  amount              : -amount
            let netDelta = oldDelta + newDelta
            if abs(netDelta) > 0.001,
               let idx = accounts.firstIndex(where: { $0.id == transaction.accountId }) {
                let newBalance = accounts[idx].balance + netDelta
                accounts[idx].balance = newBalance
                try await AccountService.shared.updateBalance(
                    accountId: transaction.accountId, newBalance: newBalance)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transfer between accounts

    func transfer(
        userId: UUID,
        fromAccountId: UUID,
        toAccountId: UUID,
        amount: Double,
        note: String?,
        date: Date
    ) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: date)

        let toName   = accounts.first { $0.id == toAccountId   }?.name ?? "account"
        let fromName = accounts.first { $0.id == fromAccountId }?.name ?? "account"
        let cleanNote = note.flatMap { $0.isEmpty ? nil : $0 }

        let expInsert = TransactionInsert(
            userId: userId, accountId: fromAccountId, categoryId: nil,
            type: "expense", amount: amount,
            description: "Transfer → \(toName)",
            note: cleanNote, date: dateStr
        )
        let incInsert = TransactionInsert(
            userId: userId, accountId: toAccountId, categoryId: nil,
            type: "income", amount: amount,
            description: "Transfer ← \(fromName)",
            note: cleanNote, date: dateStr
        )

        do {
            async let t1 = TransactionService.shared.insert(expInsert)
            async let t2 = TransactionService.shared.insert(incInsert)
            let (tx1, tx2) = try await (t1, t2)
            transactions.insert(tx1, at: 0)
            transactions.insert(tx2, at: 0)

            if let idx = accounts.firstIndex(where: { $0.id == fromAccountId }) {
                let updated = accounts[idx].balance - amount
                accounts[idx].balance = updated
                try await AccountService.shared.updateBalance(accountId: fromAccountId, newBalance: updated)
            }
            if let idx = accounts.firstIndex(where: { $0.id == toAccountId }) {
                let updated = accounts[idx].balance + amount
                accounts[idx].balance = updated
                try await AccountService.shared.updateBalance(accountId: toAccountId, newBalance: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    func delete(_ transaction: Transaction) async {
        do {
            try await TransactionService.shared.delete(id: transaction.id)
            transactions.removeAll { $0.id == transaction.id }
            let delta = transaction.type == .income ? -transaction.amount : transaction.amount
            if let idx = accounts.firstIndex(where: { $0.id == transaction.accountId }) {
                let updated = accounts[idx].balance + delta
                accounts[idx].balance = updated
                try await AccountService.shared.updateBalance(
                    accountId: transaction.accountId, newBalance: updated)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lookups

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }
}
