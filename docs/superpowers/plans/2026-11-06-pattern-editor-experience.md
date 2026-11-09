# 图纸编辑体验 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编辑画布按可读性显示色号，编辑与导出每 5 格有贯穿线，编辑页轻奶油配色并支持可撤销的左右镜像。

**Architecture:** 在 BeadCore 放置纯几何／网格变换函数，分别由 SwiftUI Canvas 与 UIKit 导出器使用；编辑器现有历史与保存路径负责镜像持久化。保留相册导出布局和列表缩略图。

**Tech Stack:** Swift 6, SwiftUI Canvas, UIKit UIGraphicsImageRenderer, BeadCore, Swift Testing, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-06-pattern-editor-and-personal-palette-design.md`

**Environment:** 当前 `xcode-select -p` 为 CommandLineTools，`xcrun simctl` 不可用；先检查 `/Applications/Xcode.app` 并在安装可用时用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`；否则如实报告无法运行模拟器／iOS 专用测试。不要声称未运行的测试通过。

**File map:**
- Create `BeadCore/Sources/BeadCore/PatternGridLayout.swift` (分组线坐标及编辑文字尺寸规则), `BeadCore/Tests/BeadCoreTests/PatternGridLayoutTests.swift`。
- Modify `BeadCore/Sources/BeadCore/PixelImage.swift` (镜像), create `BeadCore/Tests/BeadCoreTests/BeadGridMirrorTests.swift`。
- Modify `PerlerBeadApp/BeadGridCanvas.swift` (显示), `PerlerBeadApp/ExportView.swift` (导出), `PerlerBeadApp/PatternEditorView.swift` (操作／外观), `PerlerBeadApp/AppTheme.swift` (编辑页专用颜色), `PerlerBeadAppUITests/PerlerBeadAppUITests.swift` (交互)。不修改 `ThumbnailRenderer`。

### Task 1: 网格边界与色号可读性

- [ ] **Step 1: Write failing tests** — 新建 `BeadCore/Tests/BeadCoreTests/PatternGridLayoutTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("Pattern grid layout") struct PatternGridLayoutTests {
    @Test func groups() {
        #expect(PatternGridLayout.groupPositions(cellCount: 12, cellSize: 10) == [50, 100])
        #expect(PatternGridLayout.groupPositions(cellCount: 4, cellSize: 10).isEmpty)
        #expect(PatternGridLayout.groupPositions(cellCount: 10, cellSize: 10) == [50])
    }
    @Test func codeVisibility() {
        #expect(PatternGridLayout.codeFontSize(cellSize: 5, codeLength: 3) == nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 17, codeLength: 3) == nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 24, codeLength: 3) != nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 24, codeLength: 4) != nil)
    }
}
```

- [ ] **Step 2: Verify RED:** `cd BeadCore && swift test --filter PatternGridLayoutTests` → undefined `PatternGridLayout` (if platform SDK unavailable record blocker).
- [ ] **Step 3: Implement** `BeadCore/Sources/BeadCore/PatternGridLayout.swift`:

```swift
import Foundation

public enum PatternGridLayout {
    public static func groupPositions(cellCount: Int, cellSize: Double) -> [Double] {
        guard cellCount > 5, cellSize > 0 else { return [] }
        return stride(from: 5, to: cellCount, by: 5).map { Double($0) * cellSize }
    }

    public static func codeFontSize(cellSize: Double, codeLength: Int) -> Double? {
        guard cellSize >= 18, codeLength > 0 else { return nil }
        let size = min(14, min(cellSize * 0.38, (cellSize - 4) / (Double(codeLength) * 0.65)))
        return size >= 7 ? size : nil
    }
}
```

Use measured width in Canvas as a second safeguard (Core Text/SwiftUI text resolution) so long codes never overflow. A terminal boundary at 10 is already the outside border; only interior lines at 5 are added.
- [ ] **Step 4: Verify GREEN:** `cd BeadCore && swift test --filter PatternGridLayoutTests` → all tests pass.
- [ ] **Step 5: Commit:** `git add BeadCore && git commit -m "feat: define five-cell grid boundaries and label threshold"` (append session-required attribution footer).

### Task 2: 网格左右镜像

- [ ] **Step 1: Write failing test** `BeadCore/Tests/BeadCoreTests/BeadGridMirrorTests.swift`:

```swift
import Testing
@testable import BeadCore

@Suite("BeadGrid mirror") struct BeadGridMirrorTests {
    @Test func reverseEachRowIncludingEmpty() {
        let a = MardColor(code: "A1", hex: "000000")
        let b = MardColor(code: "A2", hex: "FFFFFF")
        let grid = BeadGrid(columns: 3, rows: 2, colors: [a, b, .empty, b, a, b])
        let mirrored = grid.mirroredHorizontally()
        #expect(mirrored.colors == [.empty, b, a, b, a, b])
        #expect(mirrored.mirroredHorizontally() == grid)
    }
}
```

- [ ] **Step 2: Verify RED:** `cd BeadCore && swift test --filter BeadGridMirrorTests` → missing member.
- [ ] **Step 3: Implement** at end of `BeadCore/Sources/BeadCore/PixelImage.swift`:

```swift
extension BeadGrid {
    public func mirroredHorizontally() -> BeadGrid {
        let reordered = (0..<rows).flatMap { row in
            (0..<columns).map { col in color(col: columns - col - 1, row: row) }
        }
        return BeadGrid(columns: columns, rows: rows, colors: reordered)
    }
}
```

- [ ] **Step 4: Verify GREEN:** `cd BeadCore && swift test --filter BeadGridMirrorTests` → pass.
- [ ] **Step 5: Commit** core source and test with footer.

### Task 3: 编辑画布与导出网格线

- [ ] **Step 1: Write render regression tests**: extend `PerlerBeadAppUITests/PerlerBeadAppUITests.swift` with a UI flow that creates a 16×16 test image, confirms the editor still opens, pinches in/out and remains usable. iOS UI tests cannot inspect Canvas paths directly: verify grouping and export by viewing simulator output at 5×24 pixel boundaries; do not substitute mirror-button assertions for grid-line evidence. Run the new test first for RED if simulator available.
- [ ] **Step 2: Edit** `PerlerBeadApp/BeadGridCanvas.swift`: guard per-cell `drawCenteredCode` with `PatternGridLayout.codeFontSize(cellSize: Double(cellSize), codeLength: color.code.count)`; pass computed font size into the helper; measure resolved text against `rect.width - 4` and omit if too wide. Do not draw fine per-cell strokes for empty cells, but add a separate overlay path after all cells (and before ruler labels) for both axes including empty cells:

```swift
var path = Path()
for x in PatternGridLayout.groupPositions(cellCount: grid.columns, cellSize: Double(cellSize)) {
    let px = labelMargin + CGFloat(x)
    path.move(to: CGPoint(x: px, y: labelMargin))
    path.addLine(to: CGPoint(x: px, y: labelMargin + CGFloat(grid.rows) * cellSize))
}
for y in PatternGridLayout.groupPositions(cellCount: grid.rows, cellSize: Double(cellSize)) {
    let py = labelMargin + CGFloat(y)
    path.move(to: CGPoint(x: labelMargin, y: py))
    path.addLine(to: CGPoint(x: labelMargin + CGFloat(grid.columns) * cellSize, y: py))
}
context.stroke(path, with: .color(.black.opacity(0.42)), lineWidth: 1)
```

If visual review finds fine strokes obscure color at `cellSize < 4`, skip only the fine per-cell stroke at that zoom. Keep grouping stroke in screen points, not multiplied by scale.
- [ ] **Step 3: Edit** `PerlerBeadApp/ExportView.swift`: after `drawGrid` and before `drawLabels`, draw two line sets at `origin = (28,28)` using same helper; draw straight segments with `context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.5).cgColor)`, `setLineWidth(1.2)`, `move`, `addLine`, `strokePath`. Clip only if necessary to preserve legend/ruler. Do not change `cellSize`, legend, label or transparency handling.
- [ ] **Step 4: Verify:** run `xcodegen generate` then `xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,name=<available device>' CODE_SIGNING_ALLOWED=NO test`; inspect a 100×100 editor at fit and zoom and one exported image (labels, margins, legend, transparent holes, intersections). If unavailable, report blocker and perform source-level review.
- [ ] **Step 5: Commit** canvas/export changes with footer.

### Task 4: 编辑页镜像、工具位置和奶油色

- [ ] **Step 1: Extend UI test**: after generated editor appears, assert `mirrorButton` exists; tap it, then assert undo enabled, tap undo and redo and assert editor remains usable; use test identifiers `mirrorButton`, `undoButton`, `redoButton`, `regenerateButton` for stable queries. RED: run targeted UI test before implementing.
- [ ] **Step 2: Change** `PerlerBeadApp/PatternEditorView.swift` toolbar: move existing size Button block before `toolButton(.paint, ...)`, add mirror button before `Spacer()`:

```swift
Button {
    guard let current = grid, !isRegenerating else { return }
    history.recordBeforeEdit(current)
    let mirrored = current.mirroredHorizontally()
    grid = mirrored
    saver?.scheduleSave(mirrored)
} label: {
    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
}
.disabled(grid == nil || isRegenerating)
.accessibilityLabel("左右镜像图纸")
.accessibilityIdentifier("mirrorButton")
```

Give brush, eraser, dropper and history buttons clear accessibility labels and identifiers; set brush/eraser/dropper `.foregroundStyle(selectedTool == tool ? AppTheme.coral : AppTheme.textPrimary)` and provide a selected background/shape (do not change paint behavior). Keep existing regenerate confirmation and undo/redo logic.
- [ ] **Step 3: Theme** add editor-only colors to `AppTheme.swift` (e.g. `editorBackground = Color(red:1, green:0.976, blue:0.94)`, `editorPalette = Color(red:1, green:0.945, blue:0.91)`, `editorToolbar = Color(red:1, green:0.988, blue:0.965)`) and use in editor backdrop, palette and toolbar respectively. Preserve plain white canvas backing and real bead RGB; do not change global list/generation styles.
- [ ] **Step 4: Verify GREEN** targeted UI test plus complete app build; manual review small-screen toolbar fits without clipping (reduce spacing if necessary), mirror→undo→redo→leave/reopen restores mirrored result; no mirror during regeneration.
- [ ] **Step 5: Commit** view, theme and UI tests with footer.

### Task 4b: 调整尺寸始终采用最新个人库存

- [ ] **Step 1: Add failing regression checks** to `PerlerBeadAppUITests/PerlerBeadAppUITests.swift`: use a test-only isolated `UserDefaults` suite/launch fixture to create an owned palette of one known code; generate an initial pattern with a different preset; update owned palette before tapping regenerate, confirm size, reopen and assert all produced grid codes belong to the *latest* owned palette via a package test around the extracted palette snapshot. Also test empty palette and failed persistence retain the original grid. Do not depend on visual colors alone.
- [ ] **Step 2: Add `@EnvironmentObject private var ownedPalette: OwnedPaletteModel`** to `PerlerBeadApp/PatternEditorView.swift`. In the confirmation action call `ownedPalette.refresh()`, obtain `let palette = ownedPalette.colors`, and guard nonempty before setting `isRegenerating`. On empty, show `saveResultMessage = "我的拼豆颜色库为空，请先在「我的颜色」添加颜色"` and leave grid/history unchanged.
- [ ] **Step 3: Change `regenerate(columns:)`** to accept the captured `[MardColor]` (`regenerate(columns: size, palette: palette)`). Pass `palette` into `PatternGenerationOptions(columns: columns, rows: columns, palette: palette)` inside the detached task. Never read the palette from `BeadGrid.colors`: used colors are only a subset of available inventory. A failed `downsample`/`cgImage` must reset `isRegenerating`, report an error and preserve the current grid. On return, call `try repository.updateGrid(...)` and only after that succeeds set `grid = newGrid` and `history = GridEditHistory()`; catch and report persistence failure while retaining the original grid and undo stack.
- [ ] **Step 4: Verify:** UI test and package tests on a machine with Xcode; on this machine attempt tests and record SDK blocker. Run `swiftc -frontend -parse PerlerBeadApp/*.swift` and `git diff --check`. Existing project formats remain unchanged.

### Task 5: 完整核查

- [ ] `cd BeadCore && swift test` → pass, or record toolchain blocker with actual error.
- [ ] `cd BeadPersistence && swift test` → pass, or record blocker.
- [ ] Run available simulator UI tests; check large and odd-sized patterns, empty cells, portrait/landscape and export; document tests skipped and reasons.
- [ ] `git diff --check && git status --short` → no whitespace errors or unexpected tracked files; leave `.superpowers/` untracked unless user wants it committed.
