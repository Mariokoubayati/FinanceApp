import SwiftUI

@Observable
@MainActor
final class BudgetViewModel {
    var categories:     [Category] = []
    var budgets:        [Budget]   = []
    var monthlySpending: [UUID: Double] = [:]
    var isLoading    = false
    var errorMessage: String?

    // MARK: - CategoryBudget (display model)

    struct CategoryBudget: Identifiable {
        let category: Category
        var budget: Budget?
        var spent: Double

        var id: UUID { category.id }
        var limit: Double { budget?.monthlyLimit ?? 0 }
        var progress: Double { limit > 0 ? min(spent / limit, 1.2) : 0 }
        var hasExceeded: Bool { limit > 0 && spent > limit }
    }

    var categoryBudgets: [CategoryBudget] {
        categories.map { cat in
            CategoryBudget(
                category: cat,
                budget:   budgets.first { $0.categoryId == cat.id },
                spent:    monthlySpending[cat.id] ?? 0
            )
        }
    }

    // MARK: - Load

    func load(userId: UUID) async {
        isLoading = true
        errorMessage = nil

        let cal   = Calendar.current
        let now   = Date()
        let year  = cal.component(.year,  from: now)
        let month = cal.component(.month, from: now)

        async let catsTask    = TransactionService.shared.fetchCategories()
        async let budgetsTask = BudgetService.shared.fetchAll(userId: userId)
        async let txTask      = TransactionService.shared.fetchForMonth(userId: userId,
                                                                        year: year,
                                                                        month: month)
        do {
            let (cats, bgets, txs) = try await (catsTask, budgetsTask, txTask)
            categories = cats.filter { $0.type == .expense }
            budgets    = bgets
            var spending: [UUID: Double] = [:]
            for tx in txs where tx.type == .expense {
                if let catId = tx.categoryId {
                    spending[catId, default: 0] += tx.amount
                }
            }
            monthlySpending = spending
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Set budget (insert or update)

    func setBudget(userId: UUID, categoryId: UUID, amount: Double) async {
        let upsert = BudgetUpsert(userId: userId, categoryId: categoryId, monthlyLimit: amount)
        do {
            let saved = try await BudgetService.shared.upsert(upsert)
            if let idx = budgets.firstIndex(where: { $0.categoryId == categoryId }) {
                budgets[idx] = saved
            } else {
                budgets.append(saved)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove budget

    func removeBudget(id: UUID) async {
        do {
            try await BudgetService.shared.delete(id: id)
            budgets.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
