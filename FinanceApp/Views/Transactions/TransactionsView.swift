import SwiftUI

struct TransactionsView: View {
    @Environment(AppState.self) var appState
    @State private var vm = TransactionsViewModel()
    @State private var showAdd = false
    @State private var selectedTransaction: Transaction?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Month navigator ──────────────────────────────
                HStack {
                    Button { vm.goToPreviousMonth() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text(vm.monthYearTitle).font(.headline)
                    Spacer()
                    Button { vm.goToNextMonth() } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.bold())
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // ── Monthly summary ──────────────────────────────
                let net = vm.monthlyIncome - vm.monthlyExpense
                HStack(spacing: 0) {
                    summaryItem(title: "Income",   amount: vm.monthlyIncome,  color: .green)
                    Divider().frame(height: 38)
                    summaryItem(title: "Net",      amount: net,               color: net >= 0 ? .green : .red)
                    Divider().frame(height: 38)
                    summaryItem(title: "Expenses", amount: vm.monthlyExpense, color: .red)
                }
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 10)

                // ── Type filter ──────────────────────────────────
                Picker("Filter", selection: $vm.filterType) {
                    ForEach(TransactionsViewModel.FilterType.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .onChange(of: vm.filterType) { _, _ in vm.filterCategoryId = nil }

                // ── Category chips ───────────────────────────────
                if !vm.visibleCategoryChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chipButton(title: "All",
                                       isSelected: vm.filterCategoryId == nil,
                                       color: .blue) {
                                vm.filterCategoryId = nil
                            }
                            ForEach(vm.visibleCategoryChips) { cat in
                                chipButton(
                                    title: cat.name,
                                    icon: cat.icon,
                                    isSelected: vm.filterCategoryId == cat.id,
                                    color: Color(hex: cat.color)
                                ) {
                                    vm.filterCategoryId = vm.filterCategoryId == cat.id
                                        ? nil : cat.id
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }

                // ── Transaction list ─────────────────────────────
                if vm.isLoading && vm.transactions.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filtered.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(vm.filtered) { tx in
                            Button { selectedTransaction = tx } label: {
                                TransactionRow(
                                    transaction: tx,
                                    category: vm.category(for: tx.categoryId),
                                    accountName: vm.account(for: tx.accountId)?.name
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.delete(tx) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    selectedTransaction = tx
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $vm.searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView(vm: vm).environment(appState)
            }
            .sheet(item: $selectedTransaction) { tx in
                TransactionDetailView(transaction: tx, vm: vm)
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

    // MARK: - Summary item

    private func summaryItem(title: String, amount: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD"))
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category chip

    private func chipButton(
        title: String,
        icon: String? = nil,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption2)
                }
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.18) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? color : .secondary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.4) : .clear, lineWidth: 1))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: vm.searchText.isEmpty ? "calendar.badge.clock" : "magnifyingglass")
                .font(.system(size: 60)).foregroundStyle(.secondary)
            Text(vm.searchText.isEmpty ? "No transactions" : "No results")
                .font(.title3.bold())
            Text(vm.searchText.isEmpty
                 ? "Nothing recorded for \(vm.monthYearTitle)"
                 : "Try a different search term or filter")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
