import SwiftUI

struct SavingsView: View {
    @Environment(AppState.self) var appState
    @State private var vm = SavingsViewModel()
    @State private var showAddGoal = false
    @State private var selectedGoal: SavingsGoal?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.goals.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.goals.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(vm.goals) { goal in
                                SavingsGoalCard(goal: goal) {
                                    selectedGoal = goal
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(goal) }
                                    } label: {
                                        Label("Delete Goal", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Savings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddGoal = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) {
                AddSavingsGoalView(vm: vm).environment(appState)
            }
            .sheet(item: $selectedGoal) { goal in
                ContributionSheet(goal: goal, vm: vm)
            }
            .refreshable {
                if let uid = appState.userId { await vm.load(userId: uid) }
            }
        }
        .task {
            if let uid = appState.userId { await vm.load(userId: uid) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.fill")
                .font(.system(size: 64)).foregroundStyle(.yellow)
            Text("No savings goals yet").font(.title3.bold())
            Text("Tap + to create your first goal")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
