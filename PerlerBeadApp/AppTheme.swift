import SwiftUI

enum AppTheme {
    static let coral = Color(red: 0.98, green: 0.55, blue: 0.60)
    static let coralLight = Color(red: 0.99, green: 0.93, blue: 0.94)
    static let cardBackground = Color(red: 0.99, green: 0.95, blue: 0.96)
    static let textPrimary = Color(red: 0.25, green: 0.18, blue: 0.20)

    static let cardCornerRadius: CGFloat = 16
}

struct RoundedCardButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? AppTheme.coral.opacity(0.35) : AppTheme.coralLight)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
