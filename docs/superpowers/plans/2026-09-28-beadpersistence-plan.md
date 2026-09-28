# 拼豆项目数据持久化（BeadPersistence）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个独立的 Swift Package（`BeadPersistence`），用 SwiftData 持久化拼豆项目（原图、颜色网格、缩略图），并提供一个 Repository 层封装 CRUD + 编解码 + 缩略图生成，让 UI 层不直接接触 `ModelContext`。

**Architecture:** 依赖 `BeadCore`（Plan A 产出的算法包，提供 `BeadGrid`/`MardColor` 类型）。`BeadGrid` 是纯内存值类型，不能直接被 `@Model` 持久化，因此设计一个字符串编解码层（`BeadGridCoding`）把网格序列化为逗号分隔的色号字符串存入 SwiftData；`BeadProjectRepository` 是 App 层实际会调用的入口，隐藏编解码细节。

**Tech Stack:** SwiftData（`@Model`/`ModelContainer`/`ModelContext`），ImageIO（跨平台 PNG 编码，避免拉入 UIKit/AppKit 依赖），Swift Testing。

## Global Constraints

- 依赖 Plan A 产出的 `BeadCore` 包（路径依赖 `../BeadCore`），复用其 `BeadGrid`、`MardColor`、`MardPalette` 类型，不重复定义。
- 最低平台：iOS 17 / macOS 14（与 `BeadCore` 一致，`@Model` 宏需要 iOS 17+）。
- `BeadProject.gridCodes` 用逗号分隔的 MARD 色号字符串存储（如 `"F1,C5,C5,F1"`），不使用 JSON/Codable，因为 `MardColor` 本身不需要持久化完整结构，只需色号即可在读取时对照 `MardPalette` 还原。
- 解码遇到未知色号或数量不匹配时必须 `throw`，不能静默替换为默认颜色——静默替换会在数据和色卡不一致时悄悄损坏图纸内容而不给出任何信号。
- 缩略图生成使用 `ImageIO`（`CGImageDestination`）而非 `UIImage`/`NSImage`，保证 Package 测试目标在 macOS 上可直接跑，同时产出的 PNG 数据与最终 iOS App 一致。
- 每个任务必须以 `swift test` 全绿收尾。

---

## File Structure

```
BeadPersistence/
  Package.swift                              # 依赖 BeadCore（本地路径）
  Sources/BeadPersistence/
    BeadProject.swift                        # @Model 持久化实体
    BeadGridCoding.swift                     # BeadGrid <-> gridCodes 字符串 编解码
    CGImagePNGEncoder.swift                  # ImageIO 封装的 PNG 编码（内部用）
    ThumbnailRenderer.swift                  # BeadGrid -> CGImage/PNG 缩略图渲染
    BeadProjectRepository.swift              # CRUD + 编解码 + 缩略图 的统一入口
  Tests/BeadPersistenceTests/
    BeadGridCodingTests.swift
    BeadProjectTests.swift
    ThumbnailRendererTests.swift
    BeadProjectRepositoryTests.swift
```

---

### Task 1: Package 脚手架 + SwiftData 模型

**Files:**
- Create: `BeadPersistence/Package.swift`
- Create: `BeadPersistence/Sources/BeadPersistence/BeadProject.swift`

**Interfaces:**
- Consumes: `BeadCore`（Plan A，通过本地路径依赖）
- Produces: `@Model public final class BeadProject { public var id: UUID; public var name: String; public var createdAt: Date; public var modifiedAt: Date; public var originalImageData: Data; public var columns: Int; public var rows: Int; public var gridCodes: String; public var thumbnailData: Data?; public init(id:name:createdAt:modifiedAt:originalImageData:columns:rows:gridCodes:thumbnailData:) }`

- [ ] **Step 1: 创建 Package 并链接本地 BeadCore 依赖**

前提：Plan A 已完成，`../BeadCore` 目录存在且可独立 `swift build`。

```bash
cd /Users/liuyu22/Desktop/pd
mkdir -p BeadPersistence && cd BeadPersistence
swift package init --type library --name BeadPersistence
rm -f Sources/BeadPersistence/BeadPersistence.swift Tests/BeadPersistenceTests/BeadPersistenceTests.swift
```

- [ ] **Step 2: 配置 Package.swift**

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BeadPersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeadPersistence", targets: ["BeadPersistence"]),
    ],
    dependencies: [
        .package(path: "../BeadCore"),
    ],
    targets: [
        .target(
            name: "BeadPersistence",
            dependencies: [.product(name: "BeadCore", package: "BeadCore")]
        ),
        .testTarget(
            name: "BeadPersistenceTests",
            dependencies: ["BeadPersistence"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: 写 BeadProject 模型**

创建 `Sources/BeadPersistence/BeadProject.swift`：

```swift
import BeadCore
import Foundation
import SwiftData

@Model
public final class BeadProject {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var originalImageData: Data
    public var columns: Int
    public var rows: Int
    /// Serialized grid: one MARD color code per cell, row-major, joined by "," (e.g. "A1,A1,H7,...").
    /// Stored as a flat string rather than a relationship because MardColor is a lightweight
    /// value type, not a persisted model — see BeadGridCoding for the encode/decode logic.
    public var gridCodes: String
    public var thumbnailData: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        originalImageData: Data,
        columns: Int,
        rows: Int,
        gridCodes: String,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.originalImageData = originalImageData
        self.columns = columns
        self.rows = rows
        self.gridCodes = gridCodes
        self.thumbnailData = thumbnailData
    }
}
```

- [ ] **Step 4: 编译确认无错误**

```bash
swift build
```
Expected: `Build complete!`（会先编译依赖的 `BeadCore` 包，再编译 `BeadPersistence`）

- [ ] **Step 5: Commit**

```bash
cd /Users/liuyu22/Desktop/pd
git add BeadPersistence/Package.swift BeadPersistence/Sources/BeadPersistence/BeadProject.swift BeadPersistence/.gitignore
git commit -m "feat: add BeadPersistence package scaffold with SwiftData BeadProject model"
```

---

### Task 2: BeadGrid 编解码

**Files:**
- Create: `BeadPersistence/Sources/BeadPersistence/BeadGridCoding.swift`
- Test: `BeadPersistence/Tests/BeadPersistenceTests/BeadGridCodingTests.swift`

**Interfaces:**
- Consumes: `BeadGrid`、`MardColor`（`BeadCore`，Plan A）
- Produces:
  - `public enum BeadGridCodingError: Error, Equatable { case codeCountMismatch(expected: Int, actual: Int); case unknownColorCode(String) }`
  - `public enum BeadGridCoding { public static func encode(_ grid: BeadGrid) -> String; public static func decode(_ codes: String, columns: Int, rows: Int, palette: [MardColor]) throws -> BeadGrid }`

- [ ] **Step 1: 写 BeadGridCoding**

创建 `Sources/BeadPersistence/BeadGridCoding.swift`：

```swift
import BeadCore
import Foundation

public enum BeadGridCodingError: Error, Equatable {
    case codeCountMismatch(expected: Int, actual: Int)
    case unknownColorCode(String)
}

public enum BeadGridCoding {
    private static let separator = ","

    public static func encode(_ grid: BeadGrid) -> String {
        grid.colors.map(\.code).joined(separator: separator)
    }

    /// Decodes a comma-separated code string back into a BeadGrid, resolving each code against
    /// `palette`. Throws rather than silently substituting a fallback color, since a decode
    /// failure means the persisted data and the app's palette have diverged — silently
    /// substituting would corrupt the pattern without any signal to the caller.
    public static func decode(_ codes: String, columns: Int, rows: Int, palette: [MardColor]) throws -> BeadGrid {
        let codeList = codes.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        let expectedCount = columns * rows
        guard codeList.count == expectedCount else {
            throw BeadGridCodingError.codeCountMismatch(expected: expectedCount, actual: codeList.count)
        }

        var paletteByCode: [String: MardColor] = [:]
        for color in palette {
            paletteByCode[color.code] = color
        }

        var colors = [MardColor]()
        colors.reserveCapacity(expectedCount)
        for code in codeList {
            guard let color = paletteByCode[code] else {
                throw BeadGridCodingError.unknownColorCode(code)
            }
            colors.append(color)
        }

        return BeadGrid(columns: columns, rows: rows, colors: colors)
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadPersistenceTests/BeadGridCodingTests.swift`：

```swift
import BeadCore
import Testing
@testable import BeadPersistence

@Suite("BeadGridCoding")
struct BeadGridCodingTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")

    @Test("encode joins color codes in row-major order")
    func encodeJoinsCodesInOrder() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])

        let encoded = BeadGridCoding.encode(grid)

        #expect(encoded == "F1,C5,C5,F1")
    }

    @Test("decode reconstructs a grid matching the original colors")
    func decodeRoundTripsColors() throws {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])
        let encoded = BeadGridCoding.encode(grid)

        let decoded = try BeadGridCoding.decode(encoded, columns: 2, rows: 2, palette: [Self.red, Self.blue])

        #expect(decoded == grid)
    }

    @Test("decode throws codeCountMismatch when the code count doesn't match columns * rows")
    func decodeThrowsOnCountMismatch() {
        #expect(throws: BeadGridCodingError.codeCountMismatch(expected: 4, actual: 2)) {
            try BeadGridCoding.decode("F1,C5", columns: 2, rows: 2, palette: [Self.red, Self.blue])
        }
    }

    @Test("decode throws unknownColorCode when a code isn't in the given palette")
    func decodeThrowsOnUnknownCode() {
        #expect(throws: BeadGridCodingError.unknownColorCode("Z99")) {
            try BeadGridCoding.decode("F1,Z99,C5,F1", columns: 2, rows: 2, palette: [Self.red, Self.blue])
        }
    }

    @Test("round-trip through the full MARD 221 palette preserves every color")
    func roundTripFullPalette() throws {
        let colors = MardPalette.standard221
        let grid = BeadGrid(columns: colors.count, rows: 1, colors: colors)
        let encoded = BeadGridCoding.encode(grid)

        let decoded = try BeadGridCoding.decode(encoded, columns: colors.count, rows: 1, palette: MardPalette.standard221)

        #expect(decoded == grid)
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter BeadGridCoding
```
Expected: 5 tests passed

- [ ] **Step 4: Commit**

```bash
git add BeadPersistence/Sources/BeadPersistence/BeadGridCoding.swift BeadPersistence/Tests/BeadPersistenceTests/BeadGridCodingTests.swift
git commit -m "feat: add BeadGrid string encoding/decoding for SwiftData storage"
```

---

### Task 3: SwiftData CRUD 验证（BeadProject 本身）

**Files:**
- Test: `BeadPersistence/Tests/BeadPersistenceTests/BeadProjectTests.swift`

**Interfaces:**
- Consumes: `BeadProject`（Task 1）、`BeadGridCoding`（Task 2）
- Produces: 无新公开接口，本任务用真实的内存 `ModelContainer` 验证 `BeadProject` 的插入/更新/删除/排序查询行为符合预期，为 Task 4 的 Repository 层打基础。

- [ ] **Step 1: 写测试**

创建 `Tests/BeadPersistenceTests/BeadProjectTests.swift`：

```swift
import BeadCore
import Foundation
import SwiftData
import Testing
@testable import BeadPersistence

@Suite("BeadProject")
struct BeadProjectTests {
    /// Creates a fresh in-memory ModelContainer per test so tests don't share persisted state.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([BeadProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("inserting and fetching a project round-trips all fields")
    func insertAndFetchRoundTrips() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let grid = BeadGrid(columns: 2, rows: 1, colors: [
            MardColor(code: "F1", hex: "FD957B"),
            MardColor(code: "C5", hex: "01ACEB"),
        ])
        let project = BeadProject(
            name: "Test Cat",
            createdAt: now,
            modifiedAt: now,
            originalImageData: Data([0x01, 0x02, 0x03]),
            columns: 2,
            rows: 1,
            gridCodes: BeadGridCoding.encode(grid)
        )
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())

        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Test Cat")
        #expect(fetched[0].columns == 2)
        #expect(fetched[0].rows == 1)
        #expect(fetched[0].gridCodes == "F1,C5")
        #expect(fetched[0].originalImageData == Data([0x01, 0x02, 0x03]))
    }

    @Test("updating a project's gridCodes persists the change")
    func updateProjectPersists() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let project = BeadProject(
            name: "Editable",
            createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 0),
            originalImageData: Data(),
            columns: 1,
            rows: 1,
            gridCodes: "F1"
        )
        context.insert(project)
        try context.save()

        project.gridCodes = "C5"
        project.modifiedAt = Date(timeIntervalSince1970: 100)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())
        #expect(fetched.count == 1)
        #expect(fetched[0].gridCodes == "C5")
        #expect(fetched[0].modifiedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("deleting a project removes it from subsequent fetches")
    func deleteProjectRemovesIt() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let project = BeadProject(
            name: "ToDelete",
            createdAt: Date(), modifiedAt: Date(),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "F1"
        )
        context.insert(project)
        try context.save()

        context.delete(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BeadProject>())
        #expect(fetched.isEmpty)
    }

    @Test("multiple projects can be fetched sorted by modifiedAt descending")
    func fetchSortedByModifiedAtDescending() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let older = BeadProject(
            name: "Older", createdAt: Date(timeIntervalSince1970: 0), modifiedAt: Date(timeIntervalSince1970: 0),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "F1"
        )
        let newer = BeadProject(
            name: "Newer", createdAt: Date(timeIntervalSince1970: 100), modifiedAt: Date(timeIntervalSince1970: 200),
            originalImageData: Data(), columns: 1, rows: 1, gridCodes: "C5"
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        var descriptor = FetchDescriptor<BeadProject>()
        descriptor.sortBy = [SortDescriptor(\.modifiedAt, order: .reverse)]
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.name) == ["Newer", "Older"])
    }
}
```

- [ ] **Step 2: 运行测试确认通过**

```bash
swift test --filter BeadProject
```
Expected: 4 tests passed

- [ ] **Step 3: Commit**

```bash
git add BeadPersistence/Tests/BeadPersistenceTests/BeadProjectTests.swift
git commit -m "test: verify SwiftData CRUD behavior for BeadProject"
```

---

### Task 4: 缩略图渲染

**Files:**
- Create: `BeadPersistence/Sources/BeadPersistence/CGImagePNGEncoder.swift`
- Create: `BeadPersistence/Sources/BeadPersistence/ThumbnailRenderer.swift`
- Test: `BeadPersistence/Tests/BeadPersistenceTests/ThumbnailRendererTests.swift`

**Interfaces:**
- Consumes: `BeadGrid`（`BeadCore`）
- Produces:
  - `enum CGImagePNGEncoder { static func encode(_ image: CGImage) -> Data? }`（internal，仅供 `ThumbnailRenderer` 使用）
  - `public enum ThumbnailRenderer { public static func render(_ grid: BeadGrid, cellSize: Int = 4) -> CGImage?; public static func renderPNGData(_ grid: BeadGrid, cellSize: Int = 4) -> Data? }`

⚠️ `BeadGrid` 的 row 0 是逻辑上的"第一行/顶部"，但 `CGContext` 的坐标原点在左下角，因此绘制时必须做垂直翻转（`flippedRow = grid.rows - 1 - row`），否则渲染出的缩略图会上下颠倒。

- [ ] **Step 1: 写 PNG 编码器**

创建 `Sources/BeadPersistence/CGImagePNGEncoder.swift`：

```swift
import CoreGraphics
import Foundation
import ImageIO

/// PNG encoding via ImageIO, which is available on both iOS and macOS without pulling in
/// UIKit/AppKit — keeps this package's test target buildable on macOS while producing PNG
/// data identical to what the shipped iOS app will use.
enum CGImagePNGEncoder {
    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
```

- [ ] **Step 2: 写 ThumbnailRenderer**

创建 `Sources/BeadPersistence/ThumbnailRenderer.swift`：

```swift
import BeadCore
import CoreGraphics
import Foundation

public enum ThumbnailRenderer {
    /// Renders a BeadGrid to a flat-color-per-cell CGImage at `cellSize` pixels per cell,
    /// suitable for a project list thumbnail. No grid lines or labels — those belong to the
    /// full export renderer (Plan C), not the lightweight list thumbnail.
    public static func render(_ grid: BeadGrid, cellSize: Int = 4) -> CGImage? {
        guard grid.columns > 0, grid.rows > 0, cellSize > 0 else { return nil }

        let width = grid.columns * cellSize
        let height = grid.rows * cellSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1.0)
                // Flip vertically: BeadGrid row 0 is the top row, but CGContext's origin is
                // bottom-left, so row 0 must be drawn at the highest y coordinate.
                let flippedRow = grid.rows - 1 - row
                context.fill(CGRect(x: col * cellSize, y: flippedRow * cellSize, width: cellSize, height: cellSize))
            }
        }

        return context.makeImage()
    }

    public static func renderPNGData(_ grid: BeadGrid, cellSize: Int = 4) -> Data? {
        guard let cgImage = render(grid, cellSize: cellSize) else { return nil }
        return CGImagePNGEncoder.encode(cgImage)
    }
}
```

- [ ] **Step 3: 写测试**

创建 `Tests/BeadPersistenceTests/ThumbnailRendererTests.swift`：

```swift
import BeadCore
import CoreGraphics
import ImageIO
import Testing
@testable import BeadPersistence

@Suite("ThumbnailRenderer")
struct ThumbnailRendererTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")

    @Test("render produces an image sized columns*cellSize by rows*cellSize")
    func renderProducesExpectedDimensions() {
        let grid = BeadGrid(columns: 3, rows: 2, colors: [MardColor](repeating: Self.red, count: 6))

        let image = ThumbnailRenderer.render(grid, cellSize: 4)

        #expect(image?.width == 12)
        #expect(image?.height == 8)
    }

    @Test("render returns nil for an empty grid")
    func renderReturnsNilForEmptyGrid() {
        let grid = BeadGrid(columns: 0, rows: 0, colors: [])

        let image = ThumbnailRenderer.render(grid, cellSize: 4)

        #expect(image == nil)
    }

    @Test("render draws row 0 at the top of the image despite CGContext's bottom-left origin")
    func renderPlacesRowZeroAtTop() {
        let grid = BeadGrid(columns: 1, rows: 2, colors: [Self.red, Self.blue])
        guard let image = ThumbnailRenderer.render(grid, cellSize: 2) else {
            Issue.record("expected non-nil image")
            return
        }

        var rawData = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &rawData, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let topLeftRed = rawData[0]
        let bottomLeftRowOffset = (image.height - 1) * image.width * 4
        let bottomLeftRed = rawData[bottomLeftRowOffset]

        #expect(topLeftRed > 200)
        #expect(bottomLeftRed < 100)
    }

    @Test("renderPNGData produces valid, non-empty PNG bytes")
    func renderPNGDataProducesValidPNG() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])

        let data = ThumbnailRenderer.renderPNGData(grid, cellSize: 4)

        #expect(data != nil)
        #expect((data?.count ?? 0) > 0)
        #expect(data?.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) == true)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter ThumbnailRenderer
```
Expected: 4 tests passed

- [ ] **Step 5: Commit**

```bash
git add BeadPersistence/Sources/BeadPersistence/CGImagePNGEncoder.swift BeadPersistence/Sources/BeadPersistence/ThumbnailRenderer.swift BeadPersistence/Tests/BeadPersistenceTests/ThumbnailRendererTests.swift
git commit -m "feat: add BeadGrid thumbnail rendering via ImageIO"
```

---

### Task 5: Repository 层（App 层统一入口）

**Files:**
- Create: `BeadPersistence/Sources/BeadPersistence/BeadProjectRepository.swift`
- Test: `BeadPersistence/Tests/BeadPersistenceTests/BeadProjectRepositoryTests.swift`

**Interfaces:**
- Consumes: `BeadProject`（Task 1）、`BeadGridCoding`（Task 2）、`ThumbnailRenderer`（Task 4）
- Produces: `public struct BeadProjectRepository { public init(context: ModelContext); public func createProject(name:originalImageData:grid:now:) throws -> BeadProject; public func fetchAllSortedByModifiedAtDescending() throws -> [BeadProject]; public func decodeGrid(for:palette:) throws -> BeadGrid; public func updateGrid(for:grid:now:) throws; public func delete(_:) throws }`

这是主设计文档"数据流"章节里描述的落地实现：原图存进 `originalImageData`，颜色网格编码进 `gridCodes`，缩略图在每次写入时自动重新生成——App 层（Plan C）只需要调用这一个类型，不需要知道 SwiftData 或字符串编码的存在。`now: Date` 作为参数传入而非在内部调用 `Date()`，是为了让调用方（及测试）完全控制时间戳，避免测试因真实时钟产生不确定性。

- [ ] **Step 1: 写 BeadProjectRepository**

创建 `Sources/BeadPersistence/BeadProjectRepository.swift`：

```swift
import BeadCore
import Foundation
import SwiftData

/// Application-facing repository wrapping SwiftData CRUD + BeadGrid encode/decode + thumbnail
/// generation, so the UI layer never touches ModelContext, gridCodes strings, or
/// ThumbnailRenderer directly.
public struct BeadProjectRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func createProject(name: String, originalImageData: Data, grid: BeadGrid, now: Date) throws -> BeadProject {
        let project = BeadProject(
            name: name,
            createdAt: now,
            modifiedAt: now,
            originalImageData: originalImageData,
            columns: grid.columns,
            rows: grid.rows,
            gridCodes: BeadGridCoding.encode(grid),
            thumbnailData: ThumbnailRenderer.renderPNGData(grid)
        )
        context.insert(project)
        try context.save()
        return project
    }

    public func fetchAllSortedByModifiedAtDescending() throws -> [BeadProject] {
        var descriptor = FetchDescriptor<BeadProject>()
        descriptor.sortBy = [SortDescriptor(\.modifiedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    public func decodeGrid(for project: BeadProject, palette: [MardColor]) throws -> BeadGrid {
        try BeadGridCoding.decode(project.gridCodes, columns: project.columns, rows: project.rows, palette: palette)
    }

    public func updateGrid(for project: BeadProject, grid: BeadGrid, now: Date) throws {
        project.gridCodes = BeadGridCoding.encode(grid)
        project.columns = grid.columns
        project.rows = grid.rows
        project.thumbnailData = ThumbnailRenderer.renderPNGData(grid)
        project.modifiedAt = now
        try context.save()
    }

    public func delete(_ project: BeadProject) throws {
        context.delete(project)
        try context.save()
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadPersistenceTests/BeadProjectRepositoryTests.swift`：

```swift
import BeadCore
import Foundation
import SwiftData
import Testing
@testable import BeadPersistence

@Suite("BeadProjectRepository")
struct BeadProjectRepositoryTests {
    static func makeRepository() throws -> BeadProjectRepository {
        let schema = Schema([BeadProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return BeadProjectRepository(context: ModelContext(container))
    }

    static let palette = [
        MardColor(code: "F1", hex: "FD957B"),
        MardColor(code: "C5", hex: "01ACEB"),
    ]

    @Test("createProject persists a project with encoded grid and a generated thumbnail")
    func createProjectPersistsEncodedGridAndThumbnail() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let now = Date(timeIntervalSince1970: 1000)

        let project = try repository.createProject(name: "Cat", originalImageData: Data([0xFF]), grid: grid, now: now)

        #expect(project.name == "Cat")
        #expect(project.gridCodes == "F1,C5")
        #expect(project.thumbnailData != nil)
        #expect(project.createdAt == now)
        #expect(project.modifiedAt == now)
    }

    @Test("fetchAllSortedByModifiedAtDescending returns newest-first")
    func fetchAllReturnsNewestFirst() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 1, rows: 1, colors: [Self.palette[0]])

        try repository.createProject(name: "Old", originalImageData: Data(), grid: grid, now: Date(timeIntervalSince1970: 0))
        try repository.createProject(name: "New", originalImageData: Data(), grid: grid, now: Date(timeIntervalSince1970: 500))

        let all = try repository.fetchAllSortedByModifiedAtDescending()

        #expect(all.map(\.name) == ["New", "Old"])
    }

    @Test("decodeGrid reconstructs the same BeadGrid that was originally created")
    func decodeGridReconstructsOriginal() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let project = try repository.createProject(name: "Cat", originalImageData: Data(), grid: grid, now: Date())

        let decoded = try repository.decodeGrid(for: project, palette: Self.palette)

        #expect(decoded == grid)
    }

    @Test("updateGrid overwrites gridCodes, dimensions, thumbnail, and modifiedAt")
    func updateGridOverwritesState() throws {
        let repository = try Self.makeRepository()
        let original = BeadGrid(columns: 2, rows: 1, colors: [Self.palette[0], Self.palette[1]])
        let project = try repository.createProject(
            name: "Cat", originalImageData: Data(), grid: original, now: Date(timeIntervalSince1970: 0)
        )
        let originalThumbnail = project.thumbnailData

        let updated = BeadGrid(columns: 1, rows: 2, colors: [Self.palette[1], Self.palette[0]])
        try repository.updateGrid(for: project, grid: updated, now: Date(timeIntervalSince1970: 999))

        #expect(project.gridCodes == "C5,F1")
        #expect(project.columns == 1)
        #expect(project.rows == 2)
        #expect(project.modifiedAt == Date(timeIntervalSince1970: 999))
        #expect(project.thumbnailData != originalThumbnail)
    }

    @Test("delete removes the project from subsequent fetches")
    func deleteRemovesProject() throws {
        let repository = try Self.makeRepository()
        let grid = BeadGrid(columns: 1, rows: 1, colors: [Self.palette[0]])
        let project = try repository.createProject(name: "Gone", originalImageData: Data(), grid: grid, now: Date())

        try repository.delete(project)

        let all = try repository.fetchAllSortedByModifiedAtDescending()
        #expect(all.isEmpty)
    }
}
```

- [ ] **Step 3: 运行完整测试套件确认全部通过**

```bash
swift test
```
Expected: `Test run with 18 tests in 4 suites passed`

- [ ] **Step 4: Commit**

```bash
git add BeadPersistence/Sources/BeadPersistence/BeadProjectRepository.swift BeadPersistence/Tests/BeadPersistenceTests/BeadProjectRepositoryTests.swift
git commit -m "feat: add BeadProjectRepository as unified CRUD entry point for UI layer"
```

---

## Plan Self-Review Notes

- **Spec 覆盖检查**：主设计文档"数据模型（SwiftData）"章节要求的字段（id、name、创建/修改时间、原图 Data、画布宽高、颜色网格序列化、缩略图）在 `BeadProject`（Task 1）中全部实现；"自动保存（debounce 落盘）"这一 UI 交互行为不在本 Plan 范围内（由 Plan C 的编辑器 UI 层调用 `updateGrid` 时决定 debounce 时机），但 `updateGrid` 本身（Task 5）提供了持久化落点。
- **占位符检查**：全部 5 个任务代码块均为实际编译测试通过的代码。
- **类型一致性检查**：`BeadProject`、`BeadGridCoding`、`ThumbnailRenderer`、`BeadProjectRepository` 的方法签名在任务间保持一致（已通过 `swift build`/`swift test` 交叉验证）。
- **未覆盖范围**：本 Plan 不包含 App 层如何创建/持有全局 `ModelContainer`（这是 Plan C 的 App 入口职责，因为 `ModelContainer` 的生命周期与 SwiftUI App 生命周期绑定）；也不包含"重新生成图纸时二次确认覆盖手动修改"的 UI 交互逻辑（属于 Plan C）。
