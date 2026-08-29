import SwiftUI

struct ContributionSheet: View {
    @Environment(\.dismiss) var dismiss

    let goal: SavingsGoal
    var vm: SavingsViewModel

    @State private var amountText = ""
    @State private var isLoading  = false

    private var parsedAmount: Double { Double(amountText) ?? 0 }
    private var isValid: Bool { parsedAmount > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Goal header
                VStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 56))
                        .foregroundStyle(Color(hex: goal.color))
                    Text(goal.name).font(.title2.bold())
                    Text("\(goal.remaining.formatted(.currency(code: "USD"))) remaining")
                        .font(.subheadline).foregroundStyle(.secondary)

                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.2))
                            Capsule()
                                .fill(Color(hex: goal.color))
                                .frame(width: geo.size.width * goal.progress)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                }
                .padding(.top)

                // Amount input
                VStack(spacing: 8) {
                    Text("Amount to add").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$").font(.largeTitle).foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 52, weight: .bold))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 200)
                    }
                }

                Spacer()

                Button { Task { await contribute() } } label: {
                    ZStack {
                        if isLoading { ProgressView().tint(.white) }
                        else {
                            Text("Add \(parsedAmount.formatted(.currency(code: "USD")))")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(isValid ? Color(hex: goal.color) : Color(hex: goal.color).opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
                }
                .disabled(!isValid || isLoading)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func contribute() async {
        guard isValid else { return }
        isLoading = true
        await vm.addContribution(to: goal, amount: parsedAmount)
        isLoading = false
        dismiss()
    }
}
