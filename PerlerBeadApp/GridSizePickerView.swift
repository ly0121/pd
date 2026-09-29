import PhotosUI
import SwiftUI

enum GridSizeOption: Int, CaseIterable, Identifiable {
    case s16 = 16, s24 = 24, s36 = 36, s48 = 48, s52 = 52, s68 = 68
    case s72 = 72, s78 = 78, s96 = 96, s104 = 104, s108 = 108, s128 = 128
    case s156 = 156, s200 = 200

    var id: Int { rawValue }
    var label: String { "\(rawValue)×\(rawValue)" }
}

/// Pure grid-size selection content: no navigation chrome, so it can be embedded directly in a
/// flow step (NewProjectFlowView) or wrapped in a standalone sheet (GridSizePickerSheet).
struct GridSizePickerContent: View {
    @Binding var selectedSize: Int
    var onSelect: (() -> Void)?

    @State private var customSizeText: String = ""
    @State private var showingCustomField = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(GridSizeOption.allCases) { option in
                    Button {
                        selectedSize = option.rawValue
                        onSelect?()
                    } label: {
                        Text(option.label)
                    }
                    .buttonStyle(RoundedCardButtonStyle(isSelected: selectedSize == option.rawValue))
                    .accessibilityIdentifier("gridSizeOption_\(option.rawValue)")
                }

                Button {
                    showingCustomField = true
                } label: {
                    Text("自定义")
                }
                .buttonStyle(RoundedCardButtonStyle(isSelected: showingCustomField))
            }
            .padding()

            if showingCustomField {
                HStack {
                    TextField("输入格数，如 60", text: $customSizeText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("确定") {
                        if let value = Int(customSizeText), value > 0 {
                            selectedSize = value
                            onSelect?()
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Standalone sheet wrapper for contexts where the grid size picker needs its own dismiss
/// affordance (e.g. re-opened from within the pattern editor to change an existing project's
/// grid size), as opposed to being one step inside NewProjectFlowView's own navigation flow.
struct GridSizePickerSheet: View {
    @Binding var selectedSize: Int
    /// Called right before the sheet dismisses itself, in addition to always dismissing — lets
    /// callers react to the selection (e.g. trigger a confirmation dialog) without having to
    /// reimplement the sheet's own dismiss chrome. Optional and defaults to nil so existing
    /// call sites that just want "pick a size and close" keep working unchanged.
    var onSelect: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GridSizePickerContent(selectedSize: $selectedSize, onSelect: {
                onSelect?()
                dismiss()
            })
                .background(Color.white.ignoresSafeArea())
                .navigationTitle("板子格数")
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
