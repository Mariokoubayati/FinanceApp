import SwiftUI

struct SavingsGoalCard: View {
    let goal: SavingsGoal
    var onContribute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: goal.color))
                    .frame(width: 46, height: 46)
                    .background(Color(hex: goal.color).opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name).font(.headline)
                    if let d = goal.targetDate {
                        Text("By \(d)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if goal.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.title2)
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.15))
                        Capsule()
                            .fill(Color(hex: goal.color))
                            .frame(width: max(geo.size.width * goal.progress, 0))
                            .animation(.spring(duration: 0.6), value: goal.progress)
                    }
                }
                .frame(height: 9)

                HStack {
                    Text(goal.currentAmount.formatted(.currency(code: "USD")))
                        .font(.caption.bold())
                    Spacer()
                    Text(goal.targetAmount.formatted(.currency(code: "USD")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Footer row
            HStack {
                Text("\(Int(goal.progress * 100))% complete")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !goal.isCompleted {
                    Button(action: onContribute) {
                        Text("Add Money")
                            .font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(hex: goal.color))
                            .foregroundStyle(.white)
                            .clipShape(.capsule)
                    }
                } else {
                    Text("Goal reached! 🎉")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(.secondary.opacity(0.07))
        .clipShape(.rect(cornerRadius: 18))
    }
}
