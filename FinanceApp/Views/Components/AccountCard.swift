import SwiftUI

struct AccountCard: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: account.type.icon)
                    .font(.title3).foregroundStyle(.white)
                Spacer()
                Text(account.type.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Text(account.name)
                .font(.caption).foregroundStyle(.white.opacity(0.85))
            Text(account.balance.formatted(.currency(code: account.currency)))
                .font(.title3.bold()).foregroundStyle(.white)
        }
        .padding(16)
        .frame(width: 165, height: 108)
        .background(Color(hex: account.color).gradient)
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Color(hex: account.color).opacity(0.3), radius: 8, y: 4)
    }
}
