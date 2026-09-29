import SwiftUI

enum AppTheme {
    static let coral = Color(red: 0.91, green: 0.63, blue: 0.71)       // macaron rose
    static let coralLight = Color(red: 0.99, green: 0.96, blue: 0.93)  // cream ivory
    static let cardBackground = Color(red: 1.00, green: 0.98, blue: 0.96) // cream white
    static let textPrimary = Color(red: 0.24, green: 0.17, blue: 0.17)  // warm dark brown

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
