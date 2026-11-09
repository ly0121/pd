import BeadCore
import Foundation

public struct OwnedPaletteStore {
    private let defaults: UserDefaults
    private let key = "ownedMardColorCodes.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadCodes() -> Set<String> {
        guard let saved = defaults.array(forKey: key) as? [String] else {
            return Set(MardPalette.standard221.map(\.code))
        }
        let valid = Set(MardPalette.allColors.map(\.code))
        return Set(saved).intersection(valid)
    }

    public func replaceCodes(_ codes: Set<String>) throws {
        let ordered = MardPalette.allColors.map(\.code).filter { codes.contains($0) }
        defaults.set(ordered, forKey: key)
        guard (defaults.array(forKey: key) as? [String]) == ordered else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func resolvedColors() -> [MardColor] {
        let codes = loadCodes()
        return MardPalette.allColors.filter { codes.contains($0.code) }
    }
}
