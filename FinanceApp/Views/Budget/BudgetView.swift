import SwiftUI

struct BudgetView: View {
    @Environment(AppState.self) var appState
    @State private var vm = BudgetViewModel()
    @State private var editingCategory: Category?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.categoryBudgets.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.categoryBudgets.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            summaryHeader
                        }

                        Section("Monthly Budgets") {
                            ForEach(vm.categoryBudgets) { item in
                                Button { editingCategory = item.category } label: {
                                    categoryBudgetRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .sheet(item: $editingCategory) { cat in
                BudgetEditSheet(category: cat, vm: vm)
                    .environment(appState)
            }
            .refreshable {
                if let uid = appState.userId { await vm.load(userId: uid) }
            }
        }
        .task {
            if let uid = appState.userId { await vm.load(userId: uid) }
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        let over        = vm.categoryBudgets.filter { $0.hasExceeded }
        let withBudget  = vm.categoryBudgets.filter { $0.limit > 0 }

        return VStack(alignment: .leading, spacing: 4) {
            if over.isEmpty {
                Label("All budgets on track", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
            } else {
                Label("\(over.count) categor\(over.count == 1 ? "y" : "ies") over budget",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.medium))
            }
            Text("\(withBudget.count) of \(vm.categoryBudgets.count) categories have a budget set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Category row

    private func categoryBudgetRow(_ item: BudgetViewModel.CategoryBudget) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: item.category.color).opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: item.category.icon)
                        .font(.system(size: 17))
                        .foregroundStyle(Color(hex: item.category.color))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.category.name)
                        .font(.subheadline.weight(.medium))
                    if item.limit > 0 {
                        HStack(spacing: 3) {
                            Text(item.spent, format: .currency(code: "USD"))
                                .font(.caption.bold())
                            Text("of")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.limit, format: .currency(code: "USD"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Tap to set a budget")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if item.limit > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int(min(item.progress, 1.0) * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(progressColor(item))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }

            if item.limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(progressColor(item))
                            .frame(width: geo.size.width * CGFloat(min(item.progress, 1.0)), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func progressColor(_ item: BudgetViewModel.CategoryBudget) -> Color {
        if item.hasExceeded      { return .red    }
        if item.progress > 0.8  { return .orange  }
        return .green
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 60)).foregroundStyle(.secondary)
            Text("No categories yet")
                .font(.title3.bold())
            Text("Add expense categories to start tracking budgets.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Budget edit sheet

struct BudgetEditSheet: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    let category: Category
    var vm: BudgetViewModel

    @State private var amountText: String
    @State private var isSaving = false

    init(category: Category, vm: BudgetViewModel) {
        self.category = category
        self.vm = vm
        let existing = vm.budgets.first { $0.categoryId == category.id }
        _amountText = State(initialValue: existing.map {
            String(format: "%.2f", $0.monthlyLimit)
        } ?? "")
    }

    private var existingBudget: Budget? {
        vm.budgets.first { $0.categoryId == category.id }
    }

    private var isValid: Bool {
        guard let v = Double(amountText) else { return false }
        return v > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // Category display
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: category.color).opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: category.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(Color(hex: category.color))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name).font(.headline)
                            Text("Expense category").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Budget amount
                Section("Monthly Limit") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$").foregroundStyle(.secondary).font(.title2)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                    }
                }

                // Remove (only shown if budget already exists)
                if let budget = existingBudget {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                isSaving = true
                                await vm.removeBudget(id: budget.id)
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove Budget")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = appState.userId,
                                  let amount = Double(amountText) else { return }
                            isSaving = true
                            await vm.setBudget(userId: uid,
                                               categoryId: category.id,
                                               amount: amount)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }
}
