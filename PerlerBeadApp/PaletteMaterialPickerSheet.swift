import SwiftUI

/// Pure palette-preset selection content: no navigation chrome, so it can be embedded directly
/// in a flow step or wrapped in a standalone sheet — mirrors GridSizePickerContent/Sheet's split.
struct PaletteMaterialPickerContent: View {
    @Binding var selection: PalettePreset
    var onSelect: (() -> Void)?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(PalettePreset.allCases) { preset in
                    Button {
                        selection = preset
                        onSelect?()
                    } label: {
                        Text(preset.label)
                    }
                    .buttonStyle(RoundedCardButtonStyle(isSelected: selection == preset))
                    .accessibilityIdentifier("paletteOption_\(preset)")
                }
            }
            .padding()
        }
    }
}

/// Standalone sheet wrapper for the palette material picker, opened from the generation settings
/// step — mirrors GridSizePickerSheet's structure (NavigationStack + dismiss button).
struct PaletteMaterialPickerSheet: View {
    @Binding var selection: PalettePreset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaletteMaterialPickerContent(selection: $selection, onSelect: { dismiss() })
                .background(Color.white.ignoresSafeArea())
                .navigationTitle("拼豆材料")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.coral)
                        }
                    }
                }
        }
    }
}
