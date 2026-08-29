import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard",    systemImage: "chart.pie.fill") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "arrow.left.arrow.right") }

            BudgetView()
                .tabItem { Label("Budget",       systemImage: "chart.bar.fill") }

            SavingsView()
                .tabItem { Label("Savings",      systemImage: "star.fill") }

            SettingsView()
                .tabItem { Label("Settings",     systemImage: "gear") }
        }
    }
}
