import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    let category: Category?
    var accountName: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Category icon circle
            ZStack {
                Circle()
                    .fill(Color(hex: category?.color ?? "#8E8E93").opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: category?.icon ?? "creditcard.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: category?.color ?? "#8E8E93"))
            }

            // Description + meta
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.description)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let name = accountName {
                        Text(name)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("·").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(transaction.dateValue, style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Amount
            Text((transaction.type == .income ? "+" : "–") +
                 transaction.amount.formatted(.currency(code: "USD")))
                .font(.subheadline.bold())
                .foregroundStyle(transaction.type == .income ? .green : .primary)
        }
        .padding(12)
        .background(.secondary.opacity(0.07))
        .clipShape(.rect(cornerRadius: 14))
    }
}
