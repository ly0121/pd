# 个人拼豆颜色库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在两个根级 Tab 中管理个人 MARD 颜色库存，并确保新图纸的「我的」配色只使用点击生成时的最新库存。

**Architecture:** 本机 UserDefaults 持久化库存色号，用独立可测试仓库区分未初始化与空集合；SwiftUI 库存页增删色号并同步可观察状态。生成调用点截取 palette 快照，历史项目依然由全色谱解码。

**Tech Stack:** Swift 6, SwiftUI, UserDefaults, BeadCore, Swift Testing, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-06-pattern-editor-and-personal-palette-design.md`；独立于编辑体验计划，可单独执行。

**File map:**
- Create `BeadPersistence/Sources/BeadPersistence/OwnedPaletteStore.swift`, `BeadPersistence/Tests/BeadPersistenceTests/OwnedPaletteStoreTests.swift` — 色号持久化／迁移／解析。
- Create `PerlerBeadApp/OwnedPaletteModel.swift`, `PerlerBeadApp/OwnedPaletteView.swift` — 可观察库存和管理界面。
- Modify `PerlerBeadApp/PerlerBeadApp.swift` — 根 Tab 和模型注入；`PerlerBeadApp/PalettePreset.swift` — 移除「我的」固定数量与固定取色；`PerlerBeadApp/PaletteMaterialPickerSheet.swift`, `PerlerBeadApp/NewProjectFlowView.swift` — 数量和取色快照；`PerlerBeadAppUITests/PerlerBeadAppUITests.swift` — Tab／增删／生成验证。

**Environment:** 当前 `xcode-select` 指向 CommandLineTools，`simctl` 不可用。执行时检查完整 Xcode 是否存在；如不可用，记录精确错误，不能报告模拟器测试通过。已批准默认带入 `MardPalette.standard221`；不要修改历史项目编码或它们的颜色。

### Task 1: 库存存储

- [ ] **Step 1: Write failing tests** `BeadPersistence/Tests/BeadPersistenceTests/OwnedPaletteStoreTests.swift`:

```swift
import BeadCore
import Foundation
import Testing
@testable import BeadPersistence

@Suite("Owned palette") struct OwnedPaletteStoreTests {
    @Test func initialAndEmptyStayDistinct() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnedPaletteStore(defaults: defaults)
        #expect(store.loadCodes() == Set(MardPalette.standard221.map(\.code)))
        try store.replaceCodes([])
        #expect(store.loadCodes().isEmpty)
    }
    @Test func rejectsUnknownAndDuplicateCodes() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnedPaletteStore(defaults: defaults)
        try store.replaceCodes(Set(["A1", "NOT_A_COLOR"]))
        #expect(store.loadCodes() == ["A1"])
        #expect(store.resolvedColors().map(\.code) == ["A1"])
    }
}
```

The `Set` input deduplicates codes; the valid-catalog intersection filters unknown codes.
- [ ] **Step 2: Verify RED:** `cd BeadPersistence && swift test --filter OwnedPaletteStoreTests` → missing `OwnedPaletteStore` (or record SDK blocker).
- [ ] **Step 3: Implement** in `BeadPersistence/Sources/BeadPersistence/OwnedPaletteStore.swift`:

```swift
import BeadCore
import Foundation

public struct OwnedPaletteStore {
    private let defaults: UserDefaults
    private let key = "ownedMardColorCodes.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func loadCodes() -> Set<String> {
        guard let saved = defaults.array(forKey: key) as? [String] else {
            return Set(MardPalette.standard221.map(\.code))
        }
        let valid = Set(MardPalette.allColors.map(\.code))
        return Set(saved).intersection(valid)
    }

    public func replaceCodes(_ codes: Set<String>) throws {
        let valid = Set(MardPalette.allColors.map(\.code))
        let ordered = MardPalette.allColors.map(\.code).filter { codes.contains($0) && valid.contains($0) }
        defaults.set(ordered, forKey: key)
        // UserDefaults has no per-write throwing API: verify the value read back rather than
        // inventing a guaranteed-durable transaction; notify user if readback differs.
        guard (defaults.array(forKey: key) as? [String]) == ordered else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func resolvedColors() -> [MardColor] {
        let codes = loadCodes()
        return MardPalette.allColors.filter { codes.contains($0.code) }
    }
}
```

If persistence guarantees stronger than UserDefaults readback are needed, switch to a file-backed atomic write instead; do not claim disk durability solely from immediate readback. Explicit empty `[]` remains distinct from missing key.
- [ ] **Step 4: Verify GREEN** `cd BeadPersistence && swift test --filter OwnedPaletteStoreTests` → pass.
- [ ] **Step 5: Commit** store and tests with required attribution footer.

### Task 2: 可观察状态和管理页

- [ ] **Step 1: Add UI failing checks** to `PerlerBeadAppUITests/PerlerBeadAppUITests.swift`:

```swift
func testOwnedColorsTabExists() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["我的颜色"].waitForExistence(timeout: 5))
    app.tabBars.buttons["我的颜色"].tap()
    XCTAssertTrue(app.buttons["addOwnedColorButton"].exists)
}
```

Run targeted UI test and confirm RED (if simulator available).
- [ ] **Step 2: Add** `PerlerBeadApp/OwnedPaletteModel.swift`:

```swift
import BeadCore
import BeadPersistence
import SwiftUI

@MainActor final class OwnedPaletteModel: ObservableObject {
    @Published private(set) var codes: Set<String>
    @Published var errorMessage: String?
    private let store: OwnedPaletteStore
    init(store: OwnedPaletteStore = OwnedPaletteStore()) {
        self.store = store
        codes = store.loadCodes()
    }
    var colors: [MardColor] { MardPalette.allColors.filter { codes.contains($0.code) } }
    func setOwned(_ code: String, owned: Bool) {
        guard MardPalette.allColors.contains(where: { $0.code == code }) else { return }
        var updated = codes
        if owned { updated.insert(code) } else { updated.remove(code) }
        do {
            try store.replaceCodes(updated)
            codes = store.loadCodes()
        } catch { errorMessage = "保存颜色库失败：\(error.localizedDescription)" }
    }
    func refresh() { codes = store.loadCodes() }
}
```

On first mutation the complete inherited default set is persisted minus/plus the change, so deleted colors never repopulate on relaunch.
- [ ] **Step 3: Add** `PerlerBeadApp/OwnedPaletteView.swift`: `@EnvironmentObject var ownedPalette: OwnedPaletteModel`; show `ownedPalette.colors` in `LazyVGrid` of `Circle().fill(Color(red:color.red,green:color.green,blue:color.blue))` plus `Text(color.code)` and remove button (`ownedPalette.setOwned(color.code, owned:false)`); toolbar `Button` with `accessibilityIdentifier("addOwnedColorButton")` presents a searchable sheet listing `MardPalette.allColors.filter { !ownedPalette.codes.contains($0.code) && (search.isEmpty || $0.code.localizedCaseInsensitiveContains(search)) }`; selecting a row invokes `setOwned(code, owned:true)`. Use `.alert` for `errorMessage`. Empty state says "还没有拼豆颜色，点 + 添加". Keep all buttons and cards labeled for VoiceOver. Picker displays built-in swatch and code, never raw custom RGB inputs.
- [ ] **Step 4: Modify** `PerlerBeadApp/PerlerBeadApp.swift`: `@StateObject private var ownedPalette = OwnedPaletteModel()` in `App`, wrap `ProjectListView()` and `OwnedPaletteView()` in `TabView` each with `.tabItem { Label("图纸", systemImage:"square.grid.3x3") }` and `.tabItem { Label("我的颜色", systemImage:"paintpalette") }`; `.environmentObject(ownedPalette)` on TabView, retain `.modelContainer(modelContainer)` at WindowGroup level. Verify App init/actor isolation under Swift 6; if `@StateObject` initialization conflicts with actor isolation, move it into a small root `View` with `@StateObject` and leave `App` initializer unchanged.
- [ ] **Step 5: Verify GREEN** targeted UI test; launch and search/add/remove/relaunch, ensure no duplicate color; commit model, UI, app and UI test with footer.

### Task 3: 「我的」预设使用实时库存

- [ ] **Step 1: Add regression UI test:** launch with `-UITestUseSampleImage`, switch to 我的颜色 and remove one code, switch to 图纸, go through crop/settings, assert `paletteOption_mine` label reflects reduced count; delete all in a fresh isolated test store or add an injectable empty fixture, assert generate disabled with instruction. Run targeted UI test RED.
- [ ] **Step 2: Update** `PerlerBeadApp/PalettePreset.swift`: remove the static `.mine` count and hard-coded color mapping; For `.mine` take the current snapshot only; other cases use existing arrays. Implement `label(ownedCount:)` and `colors(ownedColors:)` as complete switches over all existing cases using their current labels and `PaletteSampler.sample(count:from:)` arguments from `PalettePreset.swift`; do not leave the old `label` / `colors` properties alongside new methods because they would keep stale results. Update **all** `preset.label`, `paletteSelection.label`, and `paletteSelection.colors` call sites (use `rg 'paletteSelection|preset\.label|\.colors' PerlerBeadApp` to audit).
- [ ] **Step 3: Update** `PerlerBeadApp/PaletteMaterialPickerSheet.swift`: inject `@EnvironmentObject private var ownedPalette: OwnedPaletteModel` in content and display `preset.label(ownedCount: ownedPalette.codes.count)`; sheet inherits environment from presenter. In `PerlerBeadApp/NewProjectFlowView.swift` generation settings use the live label and show an explanatory message when `.mine` is empty; `.disabled(model.paletteSelection == .mine && ownedPalette.codes.isEmpty)` on generation button. `NewProjectFlowContentView` injects `@EnvironmentObject private var ownedPalette: OwnedPaletteModel` and passes current `ownedPalette.colors` into `model.generate(from:columns:ownedColors:)`.
- [ ] **Step 4: Modify** `NewProjectFlowModel.generate(from:columns:ownedColors:)`: `guard paletteSelection != .mine || !ownedColors.isEmpty else { step = .failed("我的拼豆颜色为空，请先在「我的颜色」添加颜色"); return }`; `let palette = paletteSelection.colors(ownedColors: ownedColors)` before the detached task; `PatternGenerationOptions(..., palette: palette)` remains unchanged. Snapshot occurs on tap, not inside detached closure. When returning to generation settings via tab navigation, call `ownedPalette.refresh()` on appearance; keep existing project loading via `MardPalette.allColors` in `BeadProjectRepository`.
- [ ] **Step 5: Verify GREEN** UI flow and regression test; verify other presets (notably `all`) produce and reopen unchanged; run `cd BeadCore && swift test`, `cd BeadPersistence && swift test`, and iOS build/UI tests when SDK available. Commit generation integration and tests with attribution footer.

### Task 4: 完整核查

- [ ] Validate fresh defaults, deletion to empty and relaunch, adding by search, duplicate suppression, latest palette on generate, other presets and old diagrams; check tab bar/navigation on a small-screen simulator.
- [ ] `git diff --check && git status --short`; document blockers, actual test results and skipped visual checks. No changes to `MardPalette.standard221` or stored project schema.
