import SwiftUI

@Observable
@MainActor
final class DashboardViewModel {
    var accounts:            [Account]     = []
    var recentTransactions:  [Transaction] = []
    var monthlyTransactions: [Transaction] = []
    var categories:          [Category]    = []
    var monthlyIncome:   Double = 0
    var monthlyExpenses: Double = 0
    var isLoading    = false
    var errorMessage: String?

    // MARK: - Simple derived values

    var totalBalance: Double {
        accounts.reduce(0) { $0 + $1.balance }
    }

    var monthlySavings: Double {
        monthlyIncome - monthlyExpenses
    }

    // MARK: - Spending by category (for donut chart)

    struct CategorySpending: Identifiable {
        var id: String { categoryName }
        let categoryName: String
        let amount: Double
        let color: String
    }

    var spendingByCategory: [CategorySpending] {
        var spending: [UUID: Double] = [:]
        for tx in monthlyTransactions where tx.type == .expense {
            if let catId = tx.categoryId {
                spending[catId, default: 0] += tx.amount
            }
        }
        return spending.compactMap { (catId, amount) -> CategorySpending? in
            guard let cat = categories.first(where: { $0.id == catId }) else { return nil }
            return CategorySpending(categoryName: cat.name, amount: amount, color: cat.color)
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: - Load

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil

        let cal   = Calendar.current
        let now   = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)

        async let accsTask    = AccountService.shared.fetchAll(userId: userId)
        async let recentTask  = TransactionService.shared.fetchRecent(userId: userId, limit: 6)
        async let monthlyTask = TransactionService.shared.fetchForMonth(userId: userId,
                                                                         year: year, month: month)
        async let catsTask    = TransactionService.shared.fetchCategories()

        do {
            let (accs, recent, monthly, cats) = try await (accsTask, recentTask, monthlyTask, catsTask)
            accounts            = accs
            recentTransactions  = recent
            monthlyTransactions = monthly
            categories          = cats
            monthlyIncome   = monthly.filter { $0.type == .income  }.reduce(0) { $0 + $1.amount }
            monthlyExpenses = monthly.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }
}
