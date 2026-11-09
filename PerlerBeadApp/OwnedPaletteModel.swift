import BeadCore
import BeadPersistence
import SwiftUI

@MainActor
final class OwnedPaletteModel: ObservableObject {
    @Published private(set) var codes: Set<String>
    @Published var errorMessage: String?
    private let store: OwnedPaletteStore

    init(store: OwnedPaletteStore = OwnedPaletteStore()) {
        self.store = store
        codes = store.loadCodes()
    }

    var colors: [MardColor] {
        MardPalette.allColors.filter { codes.contains($0.code) }
    }

    func setOwned(_ code: String, owned: Bool) {
        guard MardPalette.allColors.contains(where: { $0.code == code }) else { return }
        var updated = codes
        if owned { updated.insert(code) } else { updated.remove(code) }
        do {
            try store.replaceCodes(updated)
            codes = store.loadCodes()
        } catch {
            errorMessage = "保存颜色库失败：\(error.localizedDescription)"
        }
    }

    func refresh() {
        codes = store.loadCodes()
    }
}
