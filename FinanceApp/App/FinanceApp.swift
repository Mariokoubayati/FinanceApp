import SwiftUI

@main
struct FinanceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isLoading {
                    splashView
                } else {
                    AuthGateView()
                }
            }
            .environment(appState)
            .task {
                await appState.restoreSession()
            }
        }
    }

    private var splashView: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            Text("FinanceTracker")
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
