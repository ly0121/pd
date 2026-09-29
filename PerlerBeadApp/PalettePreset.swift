import BeadCore
import Foundation

/// Grouped color-count presets for the "拼豆材料" (bead material) picker, standing in for the
/// official MARD "12色/24色/48色/..." kits — see `PaletteSampler` for why the specific colors in
/// each numbered tier are a temporary sampling rather than the real official lineup.
enum PalettePreset: CaseIterable, Identifiable, Equatable {
    case mine
    case n12, n24, n48, n72, n96, n120, n144
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .mine: return "我的 · \(MardPalette.standard221.count)色"
        case .n12: return "基础12色"
        case .n24: return "基础24色"
        case .n48: return "基础48色"
        case .n72: return "基础72色"
        case .n96: return "基础96色"
        case .n120: return "基础120色"
        case .n144: return "基础144色"
        case .all: return "全部 · \(MardPalette.allColors.count)色"
        }
    }

    var colors: [MardColor] {
        switch self {
        case .mine: return MardPalette.standard221
        case .n12: return PaletteSampler.sample(count: 12, from: MardPalette.allColors)
        case .n24: return PaletteSampler.sample(count: 24, from: MardPalette.allColors)
        case .n48: return PaletteSampler.sample(count: 48, from: MardPalette.allColors)
        case .n72: return PaletteSampler.sample(count: 72, from: MardPalette.allColors)
        case .n96: return PaletteSampler.sample(count: 96, from: MardPalette.allColors)
        case .n120: return PaletteSampler.sample(count: 120, from: MardPalette.allColors)
        case .n144: return PaletteSampler.sample(count: 144, from: MardPalette.allColors)
        case .all: return MardPalette.allColors
        }
    }
}
