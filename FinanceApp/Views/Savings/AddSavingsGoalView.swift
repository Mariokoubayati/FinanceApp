import SwiftUI

struct AddSavingsGoalView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    var vm: SavingsViewModel

    @State private var name          = ""
    @State private var targetText    = ""
    @State private var hasDeadline   = false
    @State private var targetDate    = Date().addingTimeInterval(90 * 86400)
    @State private var selectedIcon  = "star.fill"
    @State private var selectedColor = "#FFD60A"
    @State private var isLoading     = false

    private let icons = [
        "star.fill", "house.fill", "car.fill", "airplane",
        "graduationcap.fill", "heart.fill", "gift.fill",
        "briefcase.fill", "camera.fill", "gamecontroller.fill",
        "stethoscope", "bicycle"
    ]
    private let colors = [
        "#FFD60A", "#FF6B6B", "#34C759", "#0A84FF",
        "#BF5AF2", "#FF9F0A", "#64D2FF", "#FF453A"
    ]

    var isValid: Bool {
        guard let v = Double(targetText), v > 0 else { return false }
        return !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("e.g. New MacBook, Emergency Fund", text: $name)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("Target amount", text: $targetText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Deadline") {
                    Toggle("Set a deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Target Date", selection: $targetDate,
                                   in: Date()..., displayedComponents: .date)
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundStyle(Color(hex: selectedColor))
                                .padding(10)
                                .background(selectedIcon == icon
                                    ? Color(hex: selectedColor).opacity(0.2) : .clear)
                                .clipShape(Circle())
                                .onTapGesture { selectedIcon = icon }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(!isValid || isLoading)
                }
            }
        }
    }

    private func save() async {
        guard let uid = appState.userId, let amount = Double(targetText) else { return }
        isLoading = true
        await vm.create(
            userId: uid,
            name: name,
            targetAmount: amount,
            targetDate: hasDeadline ? targetDate : nil,
            icon: selectedIcon,
            color: selectedColor
        )
        isLoading = false
        dismiss()
    }
}
