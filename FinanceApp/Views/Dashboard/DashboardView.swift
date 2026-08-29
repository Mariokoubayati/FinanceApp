import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AppState.self) var appState
    @State private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            balanceCard
                            monthlySummaryRow
                            if !vm.accounts.isEmpty { accountsSection }
                            spendingChartSection
                            recentSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .refreshable {
                if let uid = appState.userId { await vm.load(userId: uid) }
            }
        }
        .task {
            if let uid = appState.userId { await vm.load(userId: uid) }
        }
    }

    // MARK: - Balance card

    private var balanceCard: some View {
        VStack(spacing: 6) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Text(vm.totalBalance.formatted(.currency(code: "USD")))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
            Text(Date.now, style: .date)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            LinearGradient(colors: [.blue, Color(hex: "#5E5CE6")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: .blue.opacity(0.25), radius: 12, y: 6)
    }

    // MARK: - Monthly summary tiles

    private var monthlySummaryRow: some View {
        HStack(spacing: 14) {
            summaryTile(title: "Income",   amount: vm.monthlyIncome,   color: .green, icon: "arrow.down.circle.fill")
            summaryTile(title: "Expenses", amount: vm.monthlyExpenses, color: .red,   icon: "arrow.up.circle.fill")
            summaryTile(title: "Saved",    amount: vm.monthlySavings,  color: .blue,  icon: "star.fill")
        }
    }

    private func summaryTile(title: String, amount: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(amount.formatted(.currency(code: "USD")))
                .font(.subheadline.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.secondary.opacity(0.08))
        .clipShape(.rect(cornerRadius: 14))
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.accounts) { account in
                        AccountCard(account: account)
                    }
                }
            }
        }
    }

    // MARK: - Spending donut chart

    private var spendingChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spending by Category").font(.headline)

            if vm.spendingByCategory.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No expenses this month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                HStack(alignment: .center, spacing: 20) {

                    // Donut
                    ZStack {
                        Chart(vm.spendingByCategory) { item in
                            SectorMark(
                                angle: .value("Amount", item.amount),
                                innerRadius: .ratio(0.58),
                                angularInset: 2
                            )
                            .foregroundStyle(Color(hex: item.color))
                            .cornerRadius(4)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 140, height: 140)

                        VStack(spacing: 2) {
                            Text("Spent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(vm.monthlyExpenses, format: .currency(code: "USD"))
                                .font(.caption.bold())
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .frame(width: 75)
                        }
                    }

                    // Legend
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(vm.spendingByCategory.prefix(5)) { item in
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: item.color))
                                    .frame(width: 10, height: 10)
                                Text(item.categoryName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.amount, format: .currency(code: "USD"))
                                    .font(.caption.bold())
                            }
                        }
                        if vm.spendingByCategory.count > 5 {
                            Text("+ \(vm.spendingByCategory.count - 5) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent transactions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.headline)
            if vm.recentTransactions.isEmpty {
                Text("No transactions yet")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding()
            } else {
                ForEach(vm.recentTransactions) { tx in
                    TransactionRow(
                        transaction: tx,
                        category: vm.category(for: tx.categoryId)
                    )
                }
            }
        }
    }
}
