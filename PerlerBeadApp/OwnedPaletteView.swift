import BeadCore
import SwiftUI

struct OwnedPaletteView: View {
    @EnvironmentObject private var ownedPalette: OwnedPaletteModel
    @State private var showingAddColors = false
    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("\(ownedPalette.codes.count)色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .accessibilityIdentifier("ownedPaletteCount")
                if ownedPalette.colors.isEmpty {
                    ContentUnavailableView("还没有拼豆颜色", systemImage: "paintpalette", description: Text("点右上角 + 添加颜色"))
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(ownedPalette.colors, id: \.code) { color in
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                                    .frame(width: 46, height: 46)
                                    .overlay(Circle().stroke(AppTheme.textPrimary.opacity(0.15)))
                                Text(color.code)
                                    .font(.caption.weight(.medium))
                                Button("移除") { ownedPalette.setOwned(color.code, owned: false) }
                                    .font(.caption2)
                                    .accessibilityIdentifier("removeOwnedColor_\(color.code)")
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .contain)
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.coralLight.ignoresSafeArea())
            .navigationTitle("我的颜色 · \(ownedPalette.codes.count)色")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddColors = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("添加拼豆颜色")
                        .accessibilityIdentifier("addOwnedColorButton")
                }
            }
            .sheet(isPresented: $showingAddColors) {
                AddOwnedColorsView()
                    .environmentObject(ownedPalette)
            }
            .alert("保存失败", isPresented: Binding(
                get: { ownedPalette.errorMessage != nil },
                set: { if !$0 { ownedPalette.errorMessage = nil } }
            )) {
                Button("好") { ownedPalette.errorMessage = nil }
            } message: {
                Text(ownedPalette.errorMessage ?? "")
            }
        }
    }
}

private struct AddOwnedColorsView: View {
    @EnvironmentObject private var ownedPalette: OwnedPaletteModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var available: [MardColor] {
        MardPalette.allColors.filter {
            !ownedPalette.codes.contains($0.code) &&
                (search.isEmpty || $0.code.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List(available, id: \.code) { color in
                Button {
                    ownedPalette.setOwned(color.code, owned: true)
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(AppTheme.textPrimary.opacity(0.15)))
                        Text(color.code)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .accessibilityIdentifier("addOwnedColor_\(color.code)")
            }
            .searchable(text: $search, prompt: "搜索 MARD 色号")
            .navigationTitle("添加颜色")
            .alert("保存失败", isPresented: Binding(
                get: { ownedPalette.errorMessage != nil },
                set: { if !$0 { ownedPalette.errorMessage = nil } }
            )) {
                Button("好") { ownedPalette.errorMessage = nil }
            } message: {
                Text(ownedPalette.errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
