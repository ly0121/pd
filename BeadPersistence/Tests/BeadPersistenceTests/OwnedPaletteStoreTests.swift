import BeadCore
import Foundation
import Testing
@testable import BeadPersistence

@Suite("Owned palette")
struct OwnedPaletteStoreTests {
    @Test func defaultAndExplicitEmptyAreDifferent() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnedPaletteStore(defaults: defaults)
        #expect(store.loadCodes() == Set(MardPalette.standard221.map(\.code)))
        try store.replaceCodes([])
        #expect(store.loadCodes().isEmpty)
        #expect(OwnedPaletteStore(defaults: defaults).loadCodes().isEmpty)
    }

    @Test func currentColorsAreResolvedOnEveryRead() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnedPaletteStore(defaults: defaults)
        try store.replaceCodes(["A1"])
        let firstSnapshot = store.resolvedColors()
        try store.replaceCodes(["B1"])
        #expect(firstSnapshot.map(\.code) == ["A1"])
        #expect(store.resolvedColors().map(\.code) == ["B1"])
    }

    @Test func filtersUnknownCodesAndOrdersResolvedColors() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnedPaletteStore(defaults: defaults)
        try store.replaceCodes(["B1", "A1", "NOT_A_COLOR"])
        #expect(store.loadCodes() == ["A1", "B1"])
        #expect(store.resolvedColors().map(\.code) == ["A1", "B1"])
    }
}
