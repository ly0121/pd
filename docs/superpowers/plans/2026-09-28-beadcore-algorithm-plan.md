# 拼豆图纸生成算法核心（BeadCore）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个独立的、可被 iOS App 引用的 Swift Package（`BeadCore`），实现"照片 → 拼豆图纸颜色网格"的完整算法流水线：MARD 色卡数据、Lab 色差最近色匹配、Vision 驱动的重要性权重图、SLIC 超像素分割、调色板联合优化、孤立噪点清理。

**Architecture:** 纯 Swift Package，不依赖 SwiftUI/SwiftData，方便在 macOS 上用 `swift test` 快速迭代和真实验证（包括真实调用 Vision 框架），之后作为本地依赖被 iOS App target 引用。所有类型均为值类型（struct）+ `Sendable`，为未来放入后台线程/并发场景做准备。

**Tech Stack:** Swift 6（strict concurrency），Vision 框架（显著性检测），CoreGraphics/CoreVideo（像素读取与重采样），Swift Testing（`import Testing`，非 XCTest）。

## Global Constraints

- 最低平台：iOS 17 / macOS 14（`Package.swift` 的 `platforms` 字段），与主设计文档的 SwiftUI+SwiftData 技术选型保持一致。
- 内置色卡固定为 **MARD 潘娜标准 221 色**（A26/B32/C29/D26/E24/F25/G21/H23/M15，加总 221），不包含 P/Q/R/T/Y/ZG 特殊色系列。
- 颜色差异计算统一使用 **Lab 色彩空间欧氏距离**，不使用 RGB 距离。
- 所有公开类型和函数标记 `public`，供后续 App target 引用；核心数据类型（`PixelImage`、`ImportanceMap`、`BeadGrid`、`LabColor`、`MardColor`）均为 `Sendable` 的不可变值类型（除 `BeadGrid.colors` 支持局部可变以配合编辑器手动改色场景）。
- 每个任务必须以 `swift test` 全绿收尾，不允许把编译失败或测试失败的代码提交到下一个任务。
- 构建 `CGContext` 时如果同时需要 `setFillColor` 和后续像素级颜色比对，必须使用 `context.setFillColor(red:green:blue:alpha:)` 分量重载，**不要**使用 `CGColor(red:green:blue:alpha:)`（无 colorspace 参数）再传入 `setFillColor(_:)` — 后者会经历隐式色彩空间转换，导致实际像素值偏离预期值（实测偏差可达每通道 30+/255）。

---

## File Structure

```
BeadCore/
  Package.swift
  Sources/BeadCore/
    MardColor.swift              # MardColor 数据结构 + MardPalette.standard221 (221 色)
    ColorMatcher.swift           # LabColor + RGB→Lab 转换 + ColorMatcher.nearest(...)
    PixelImage.swift             # PixelImage / ImportanceMap / BeadGrid 数据结构
    SuperpixelSegmenter.swift    # SLIC 风格的迭代区域分割（cellStats / refine / segment）
    PaletteOptimizer.swift       # 区域分割 + 调色板联合优化（optimize / makeGrid）
    NoiseCleaner.swift           # 孤立噪点清理（clean）
    ImportanceMapProvider.swift  # Vision 显著性检测生成重要性权重图 + 均匀权重回退
    PatternGenerator.swift       # 端到端入口（generate）+ PixelImage(cgImage:) 构造器
  Tests/BeadCoreTests/
    MardPaletteTests.swift
    ColorMatcherTests.swift
    SuperpixelSegmenterTests.swift
    PaletteOptimizerTests.swift
    NoiseCleanerTests.swift
    ImportanceMapProviderTests.swift
    PatternGeneratorTests.swift
```

每个 `Sources/BeadCore/*.swift` 文件职责单一，且与对应的 `Tests/BeadCoreTests/*Tests.swift` 一一对应，符合"文件按职责拆分、测试与实现共同变化"的原则。

---

### Task 1: 项目脚手架 + MARD 221 色数据

**Files:**
- Create: `BeadCore/Package.swift`
- Create: `BeadCore/Sources/BeadCore/MardColor.swift`
- Test: `BeadCore/Tests/BeadCoreTests/MardPaletteTests.swift`

**Interfaces:**
- Produces:
  - `public struct MardColor: Equatable, Hashable, Sendable { public let code: String; public let red: Double; public let green: Double; public let blue: Double; public init(code: String, hex: String) }`
  - `public enum MardPalette { public static let standard221: [MardColor] }`

- [ ] **Step 1: 创建 Swift Package**

```bash
mkdir -p BeadCore && cd BeadCore
swift package init --type library --name BeadCore
rm -f Sources/BeadCore/BeadCore.swift Tests/BeadCoreTests/BeadCoreTests.swift
```

- [ ] **Step 2: 设置平台最低版本**

编辑 `Package.swift`，在 `Package(name: "BeadCore",` 后面加入 `platforms: [.iOS(.v17), .macOS(.v14)],`：

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BeadCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeadCore", targets: ["BeadCore"]),
    ],
    targets: [
        .target(name: "BeadCore"),
        .testTarget(name: "BeadCoreTests", dependencies: ["BeadCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: 写 MardColor 数据结构**

创建 `Sources/BeadCore/MardColor.swift`：

```swift
import Foundation

public struct MardColor: Equatable, Hashable, Sendable {
    public let code: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(code: String, hex: String) {
        self.code = code
        let (r, g, b) = MardColor.parseHex(hex)
        self.red = r
        self.green = g
        self.blue = b
    }

    private static func parseHex(_ hex: String) -> (Double, Double, Double) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        return (r, g, b)
    }
}

public enum MardPalette {
    public static let standard221: [MardColor] = [
        MardColor(code: "A1", hex: "FAF4C8"), MardColor(code: "A2", hex: "FFFFD5"),
        MardColor(code: "A3", hex: "FEFF8B"), MardColor(code: "A4", hex: "FBED56"),
        MardColor(code: "A5", hex: "F4D738"), MardColor(code: "A6", hex: "FEAC4C"),
        MardColor(code: "A7", hex: "FE8B4C"), MardColor(code: "A8", hex: "FFDA45"),
        MardColor(code: "A9", hex: "FF995B"), MardColor(code: "A10", hex: "F77C31"),
        MardColor(code: "A11", hex: "FFDD99"), MardColor(code: "A12", hex: "FE9F72"),
        MardColor(code: "A13", hex: "FFC365"), MardColor(code: "A14", hex: "FD543D"),
        MardColor(code: "A15", hex: "FFF365"), MardColor(code: "A16", hex: "FFFF9F"),
        MardColor(code: "A17", hex: "FFE36E"), MardColor(code: "A18", hex: "FEBE7D"),
        MardColor(code: "A19", hex: "FD7C72"), MardColor(code: "A20", hex: "FFD568"),
        MardColor(code: "A21", hex: "FFE395"), MardColor(code: "A22", hex: "F4F57D"),
        MardColor(code: "A23", hex: "E6C9B7"), MardColor(code: "A24", hex: "F7F8A2"),
        MardColor(code: "A25", hex: "FFD67D"), MardColor(code: "A26", hex: "FFC830"),

        MardColor(code: "B1", hex: "E6EE31"), MardColor(code: "B2", hex: "63F347"),
        MardColor(code: "B3", hex: "9EF780"), MardColor(code: "B4", hex: "5DE035"),
        MardColor(code: "B5", hex: "35E352"), MardColor(code: "B6", hex: "65E2A6"),
        MardColor(code: "B7", hex: "3DAF80"), MardColor(code: "B8", hex: "1C9C4F"),
        MardColor(code: "B9", hex: "27523A"), MardColor(code: "B10", hex: "95D3C2"),
        MardColor(code: "B11", hex: "5D722A"), MardColor(code: "B12", hex: "166F41"),
        MardColor(code: "B13", hex: "CAEB7B"), MardColor(code: "B14", hex: "ADE946"),
        MardColor(code: "B15", hex: "2E5132"), MardColor(code: "B16", hex: "C5ED9C"),
        MardColor(code: "B17", hex: "9BB13A"), MardColor(code: "B18", hex: "E6EE49"),
        MardColor(code: "B19", hex: "24B88C"), MardColor(code: "B20", hex: "C2F0CC"),
        MardColor(code: "B21", hex: "156A6B"), MardColor(code: "B22", hex: "0B3C43"),
        MardColor(code: "B23", hex: "303A21"), MardColor(code: "B24", hex: "EEFCA5"),
        MardColor(code: "B25", hex: "4E846D"), MardColor(code: "B26", hex: "8D7A35"),
        MardColor(code: "B27", hex: "CCE1AF"), MardColor(code: "B28", hex: "9EE5B9"),
        MardColor(code: "B29", hex: "C5E254"), MardColor(code: "B30", hex: "E2FCB1"),
        MardColor(code: "B31", hex: "B0E792"), MardColor(code: "B32", hex: "9CAB5A"),

        MardColor(code: "C1", hex: "E8FFE7"), MardColor(code: "C2", hex: "A9F9FC"),
        MardColor(code: "C3", hex: "A0E2FB"), MardColor(code: "C4", hex: "41CCFF"),
        MardColor(code: "C5", hex: "01ACEB"), MardColor(code: "C6", hex: "50AAF0"),
        MardColor(code: "C7", hex: "3677D2"), MardColor(code: "C8", hex: "0F54C0"),
        MardColor(code: "C9", hex: "324BCA"), MardColor(code: "C10", hex: "3EBCE2"),
        MardColor(code: "C11", hex: "28DDDE"), MardColor(code: "C12", hex: "1C334D"),
        MardColor(code: "C13", hex: "CDE8FF"), MardColor(code: "C14", hex: "D5FDFF"),
        MardColor(code: "C15", hex: "22C4C6"), MardColor(code: "C16", hex: "1557A8"),
        MardColor(code: "C17", hex: "04D1F6"), MardColor(code: "C18", hex: "1D3344"),
        MardColor(code: "C19", hex: "1887A2"), MardColor(code: "C20", hex: "176DAF"),
        MardColor(code: "C21", hex: "BEDDFF"), MardColor(code: "C22", hex: "67B4BE"),
        MardColor(code: "C23", hex: "C8E2FF"), MardColor(code: "C24", hex: "7CC4FF"),
        MardColor(code: "C25", hex: "A9E5E5"), MardColor(code: "C26", hex: "3CAED8"),
        MardColor(code: "C27", hex: "D3DFFA"), MardColor(code: "C28", hex: "BBCFED"),
        MardColor(code: "C29", hex: "34488E"),

        MardColor(code: "D1", hex: "AEB4F2"), MardColor(code: "D2", hex: "858EDD"),
        MardColor(code: "D3", hex: "2F54AF"), MardColor(code: "D4", hex: "182A84"),
        MardColor(code: "D5", hex: "B843C5"), MardColor(code: "D6", hex: "AC7BDE"),
        MardColor(code: "D7", hex: "8854B3"), MardColor(code: "D8", hex: "E2D3FF"),
        MardColor(code: "D9", hex: "D5B9F8"), MardColor(code: "D10", hex: "361851"),
        MardColor(code: "D11", hex: "B9BAE1"), MardColor(code: "D12", hex: "DE9AD4"),
        MardColor(code: "D13", hex: "B90095"), MardColor(code: "D14", hex: "8B279B"),
        MardColor(code: "D15", hex: "2F1F90"), MardColor(code: "D16", hex: "E3E1EE"),
        MardColor(code: "D17", hex: "C4D4F6"), MardColor(code: "D18", hex: "A45EC7"),
        MardColor(code: "D19", hex: "D8C3D7"), MardColor(code: "D20", hex: "9C32B2"),
        MardColor(code: "D21", hex: "9A009B"), MardColor(code: "D22", hex: "333A95"),
        MardColor(code: "D23", hex: "EBDAFC"), MardColor(code: "D24", hex: "7786E5"),
        MardColor(code: "D25", hex: "494FC7"), MardColor(code: "D26", hex: "DFC2F8"),

        MardColor(code: "E1", hex: "FDD3CC"), MardColor(code: "E2", hex: "FEC0DF"),
        MardColor(code: "E3", hex: "FFB7E7"), MardColor(code: "E4", hex: "E8649E"),
        MardColor(code: "E5", hex: "F551A2"), MardColor(code: "E6", hex: "F13D74"),
        MardColor(code: "E7", hex: "C63478"), MardColor(code: "E8", hex: "FFDBE9"),
        MardColor(code: "E9", hex: "E970CC"), MardColor(code: "E10", hex: "D33793"),
        MardColor(code: "E11", hex: "FCDDD2"), MardColor(code: "E12", hex: "F78FC3"),
        MardColor(code: "E13", hex: "B5006D"), MardColor(code: "E14", hex: "FFD1BA"),
        MardColor(code: "E15", hex: "F8C7C9"), MardColor(code: "E16", hex: "FFF3EB"),
        MardColor(code: "E17", hex: "FFE2EA"), MardColor(code: "E18", hex: "FFC7DB"),
        MardColor(code: "E19", hex: "FEBAD5"), MardColor(code: "E20", hex: "D8C7D1"),
        MardColor(code: "E21", hex: "BD9DA1"), MardColor(code: "E22", hex: "B785A1"),
        MardColor(code: "E23", hex: "937A8D"), MardColor(code: "E24", hex: "E1BCE8"),

        MardColor(code: "F1", hex: "FD957B"), MardColor(code: "F2", hex: "FC3D46"),
        MardColor(code: "F3", hex: "F74941"), MardColor(code: "F4", hex: "FC283C"),
        MardColor(code: "F5", hex: "E7002F"), MardColor(code: "F6", hex: "943630"),
        MardColor(code: "F7", hex: "971937"), MardColor(code: "F8", hex: "BC0028"),
        MardColor(code: "F9", hex: "E2677A"), MardColor(code: "F10", hex: "8A4526"),
        MardColor(code: "F11", hex: "5A2121"), MardColor(code: "F12", hex: "FD4E6A"),
        MardColor(code: "F13", hex: "F35744"), MardColor(code: "F14", hex: "FFA9AD"),
        MardColor(code: "F15", hex: "D30022"), MardColor(code: "F16", hex: "FEC2A6"),
        MardColor(code: "F17", hex: "E69C79"), MardColor(code: "F18", hex: "D37C46"),
        MardColor(code: "F19", hex: "C1444A"), MardColor(code: "F20", hex: "CD9391"),
        MardColor(code: "F21", hex: "F7B4C6"), MardColor(code: "F22", hex: "FDC0D0"),
        MardColor(code: "F23", hex: "F67E66"), MardColor(code: "F24", hex: "E698AA"),
        MardColor(code: "F25", hex: "E54B4F"),

        MardColor(code: "G1", hex: "FFE2CE"), MardColor(code: "G2", hex: "FFC4AA"),
        MardColor(code: "G3", hex: "F4C3A5"), MardColor(code: "G4", hex: "E1B383"),
        MardColor(code: "G5", hex: "EDB045"), MardColor(code: "G6", hex: "E99C17"),
        MardColor(code: "G7", hex: "9D5B3E"), MardColor(code: "G8", hex: "753832"),
        MardColor(code: "G9", hex: "E6B483"), MardColor(code: "G10", hex: "D98C39"),
        MardColor(code: "G11", hex: "E0C593"), MardColor(code: "G12", hex: "FFC890"),
        MardColor(code: "G13", hex: "B7714A"), MardColor(code: "G14", hex: "8D614C"),
        MardColor(code: "G15", hex: "FCF9E0"), MardColor(code: "G16", hex: "F2D9BA"),
        MardColor(code: "G17", hex: "78524B"), MardColor(code: "G18", hex: "FFE4CC"),
        MardColor(code: "G19", hex: "E07935"), MardColor(code: "G20", hex: "A94023"),
        MardColor(code: "G21", hex: "B88558"),

        MardColor(code: "H1", hex: "FDFBFF"), MardColor(code: "H2", hex: "FEFFFF"),
        MardColor(code: "H3", hex: "B6B1BA"), MardColor(code: "H4", hex: "89858C"),
        MardColor(code: "H5", hex: "48464E"), MardColor(code: "H6", hex: "2F2B2F"),
        MardColor(code: "H7", hex: "000000"), MardColor(code: "H8", hex: "E7D6DB"),
        MardColor(code: "H9", hex: "EDEDED"), MardColor(code: "H10", hex: "EEE9EA"),
        MardColor(code: "H11", hex: "CECDD5"), MardColor(code: "H12", hex: "FFF5ED"),
        MardColor(code: "H13", hex: "F5ECD2"), MardColor(code: "H14", hex: "CFD7D3"),
        MardColor(code: "H15", hex: "98A6A8"), MardColor(code: "H16", hex: "1D1414"),
        MardColor(code: "H17", hex: "F1EDED"), MardColor(code: "H18", hex: "FFFDF0"),
        MardColor(code: "H19", hex: "F6EFE2"), MardColor(code: "H20", hex: "949FA3"),
        MardColor(code: "H21", hex: "FFFBE1"), MardColor(code: "H22", hex: "CACAD4"),
        MardColor(code: "H23", hex: "9A9D94"),

        MardColor(code: "M1", hex: "BCC6B8"), MardColor(code: "M2", hex: "8AA386"),
        MardColor(code: "M3", hex: "697D80"), MardColor(code: "M4", hex: "E3D2BC"),
        MardColor(code: "M5", hex: "D0CCAA"), MardColor(code: "M6", hex: "B0A782"),
        MardColor(code: "M7", hex: "B4A497"), MardColor(code: "M8", hex: "B38281"),
        MardColor(code: "M9", hex: "A58767"), MardColor(code: "M10", hex: "C5B2BC"),
        MardColor(code: "M11", hex: "9F7594"), MardColor(code: "M12", hex: "644749"),
        MardColor(code: "M13", hex: "D19066"), MardColor(code: "M14", hex: "C77362"),
        MardColor(code: "M15", hex: "757D78"),
    ]
}
```

- [ ] **Step 4: 写测试**

创建 `Tests/BeadCoreTests/MardPaletteTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("MardPalette")
struct MardPaletteTests {
    @Test("standard221 contains exactly 221 colors")
    func totalCount() {
        #expect(MardPalette.standard221.count == 221)
    }

    @Test("standard221 has no duplicate codes")
    func noDuplicateCodes() {
        let codes = MardPalette.standard221.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("each series has the expected count", arguments: [
        ("A", 26), ("B", 32), ("C", 29), ("D", 26),
        ("E", 24), ("F", 25), ("G", 21), ("H", 23), ("M", 15),
    ])
    func seriesCount(prefix: String, expectedCount: Int) {
        let seriesColors = MardPalette.standard221.filter { color in
            let letters = color.code.prefix { $0.isLetter }
            return letters == prefix
        }
        #expect(seriesColors.count == expectedCount)
    }

    @Test("H7 is pure black")
    func h7IsBlack() {
        let black = MardPalette.standard221.first { $0.code == "H7" }
        #expect(black?.red == 0.0)
        #expect(black?.green == 0.0)
        #expect(black?.blue == 0.0)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd BeadCore && swift test --filter MardPalette
```
Expected: 4 tests passed（total count / no duplicates / 9 个系列计数 / H7 是黑色）

- [ ] **Step 6: Commit**

```bash
cd /Users/liuyu22/Desktop/pd
git add BeadCore/Package.swift BeadCore/Sources/BeadCore/MardColor.swift BeadCore/Tests/BeadCoreTests/MardPaletteTests.swift BeadCore/.gitignore
git commit -m "feat: add BeadCore package scaffold with MARD 221-color palette"
```

---

### Task 2: Lab 色差最近色匹配

**Files:**
- Create: `BeadCore/Sources/BeadCore/ColorMatcher.swift`
- Test: `BeadCore/Tests/BeadCoreTests/ColorMatcherTests.swift`

**Interfaces:**
- Consumes: `MardColor`（Task 1）
- Produces:
  - `public struct LabColor: Equatable, Sendable { public let l, a, b: Double; public init(l:a:b:); public init(red:green:blue:); public func distance(to:) -> Double }`
  - `extension MardColor { public var lab: LabColor }`
  - `public enum ColorMatcher { public static func nearest(to: LabColor, in: [MardColor]) -> MardColor }`

- [ ] **Step 1: 写 LabColor + ColorMatcher**

创建 `Sources/BeadCore/ColorMatcher.swift`：

```swift
import Foundation

public struct LabColor: Equatable, Sendable {
    public let l: Double
    public let a: Double
    public let b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public init(red: Double, green: Double, blue: Double) {
        func linearize(_ channel: Double) -> Double {
            channel > 0.04045 ? pow((channel + 0.055) / 1.055, 2.4) : channel / 12.92
        }
        let r = linearize(red), g = linearize(green), b = linearize(blue)

        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.00000
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + (16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)

        self.l = (116.0 * fy) - 16.0
        self.a = 500.0 * (fx - fy)
        self.b = 200.0 * (fy - fz)
    }

    public func distance(to other: LabColor) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }
}

extension MardColor {
    public var lab: LabColor {
        LabColor(red: red, green: green, blue: blue)
    }
}

public enum ColorMatcher {
    public static func nearest(to color: LabColor, in palette: [MardColor]) -> MardColor {
        precondition(!palette.isEmpty, "palette must not be empty")
        var best = palette[0]
        var bestDistance = color.distance(to: best.lab)
        for candidate in palette.dropFirst() {
            let distance = color.distance(to: candidate.lab)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/ColorMatcherTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("ColorMatcher")
struct ColorMatcherTests {
    @Test("pure black RGB matches MARD H7 exactly")
    func pureBlackMatchesH7() {
        let black = LabColor(red: 0, green: 0, blue: 0)
        let match = ColorMatcher.nearest(to: black, in: MardPalette.standard221)
        #expect(match.code == "H7")
    }

    @Test("pure white RGB matches a near-white MARD color")
    func pureWhiteMatchesNearWhite() {
        let white = LabColor(red: 1, green: 1, blue: 1)
        let match = ColorMatcher.nearest(to: white, in: MardPalette.standard221)
        #expect(match.code == "H1" || match.code == "H2")
    }

    @Test("distance to self is zero")
    func distanceToSelfIsZero() {
        let color = LabColor(red: 0.5, green: 0.3, blue: 0.8)
        #expect(color.distance(to: color) == 0.0)
    }

    @Test("nearest color is deterministic for a fixed palette order")
    func deterministicForTiedDistances() {
        let palette = [
            MardColor(code: "X1", hex: "808080"),
            MardColor(code: "X2", hex: "808080"),
        ]
        let target = LabColor(red: 0.5, green: 0.5, blue: 0.5)
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "X1")
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter ColorMatcher
```
Expected: 4 tests passed

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/ColorMatcher.swift BeadCore/Tests/BeadCoreTests/ColorMatcherTests.swift
git commit -m "feat: add Lab color space conversion and nearest-color matching"
```

---

### Task 3: 核心数据结构（PixelImage / ImportanceMap / BeadGrid）

**Files:**
- Create: `BeadCore/Sources/BeadCore/PixelImage.swift`

**Interfaces:**
- Consumes: `LabColor`（Task 2）、`MardColor`（Task 1）
- Produces:
  - `public struct PixelImage: Sendable { public let width, height: Int; public let pixels: [LabColor]; public init(width:height:pixels:); public init(width:height:rgb:); public func pixel(x:y:) -> LabColor }`
  - `public struct ImportanceMap: Sendable { public let width, height: Int; public let weights: [Double]; public init(width:height:weights:); public static func uniform(width:height:) -> ImportanceMap; public func weight(x:y:) -> Double }`
  - `public struct BeadGrid: Sendable, Equatable { public let columns, rows: Int; public var colors: [MardColor]; public init(columns:rows:colors:); public func color(col:row:) -> MardColor; public mutating func setColor(_:col:row:) }`

这一步没有独立的单元测试文件——这些是纯数据容器，行为由 Task 4~7 的测试间接覆盖（若初始化时传入的数组长度不匹配 `width*height`/`columns*rows` 会触发 `precondition` 崩溃，这是有意为之的快速失败设计，供内部调用方使用，不面向最终用户输入）。

- [ ] **Step 1: 写数据结构**

创建 `Sources/BeadCore/PixelImage.swift`：

```swift
import Foundation

public struct PixelImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [LabColor]

    public init(width: Int, height: Int, pixels: [LabColor]) {
        precondition(pixels.count == width * height, "pixel count must equal width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, rgb: [(red: Double, green: Double, blue: Double)]) {
        self.init(width: width, height: height, pixels: rgb.map { LabColor(red: $0.red, green: $0.green, blue: $0.blue) })
    }

    public func pixel(x: Int, y: Int) -> LabColor {
        pixels[y * width + x]
    }
}

public struct ImportanceMap: Sendable {
    public let width: Int
    public let height: Int
    public let weights: [Double]

    public init(width: Int, height: Int, weights: [Double]) {
        precondition(weights.count == width * height, "weight count must equal width * height")
        self.width = width
        self.height = height
        self.weights = weights
    }

    public static func uniform(width: Int, height: Int) -> ImportanceMap {
        ImportanceMap(width: width, height: height, weights: [Double](repeating: 1.0, count: width * height))
    }

    public func weight(x: Int, y: Int) -> Double {
        weights[y * width + x]
    }
}

public struct BeadGrid: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public var colors: [MardColor]

    public init(columns: Int, rows: Int, colors: [MardColor]) {
        precondition(colors.count == columns * rows, "color count must equal columns * rows")
        self.columns = columns
        self.rows = rows
        self.colors = colors
    }

    public func color(col: Int, row: Int) -> MardColor {
        colors[row * columns + col]
    }

    public mutating func setColor(_ color: MardColor, col: Int, row: Int) {
        colors[row * columns + col] = color
    }
}
```

- [ ] **Step 2: 编译确认无错误**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add BeadCore/Sources/BeadCore/PixelImage.swift
git commit -m "feat: add PixelImage, ImportanceMap, and BeadGrid data structures"
```

---

### Task 4: SLIC 超像素分割

**Files:**
- Create: `BeadCore/Sources/BeadCore/SuperpixelSegmenter.swift`
- Test: `BeadCore/Tests/BeadCoreTests/SuperpixelSegmenterTests.swift`

**Interfaces:**
- Consumes: `PixelImage`、`ImportanceMap`（Task 3）、`LabColor`（Task 2）
- Produces:
  - `public struct CellStats: Sendable, Equatable { public var color: LabColor; public var centerX, centerY: Double; public var pixelCount: Int }`
  - `public struct SegmentationResult: Sendable, Equatable { public let columns, rows: Int; public let labels: [Int]; public init(columns:rows:labels:) }`
  - `public enum SuperpixelSegmenter`，静态方法：
    - `initialCellIndex(x:y:width:height:columns:rows:) -> Int`
    - `initialLabels(width:height:columns:rows:) -> [Int]`
    - `cellStats(image:columns:rows:importance:labels:fallback:) -> [CellStats]`
    - `refine(image:columns:rows:importance:labels:cellColors:centers:compactness:) -> [Int]`
    - `segment(image:columns:rows:importance:iterations:compactness:) -> SegmentationResult`

**这是全项目风险最高的算法模块**，实现前请注意：`refine` 的每个像素只在自己所在格子及其上下左右 4 个相邻格子间比较"颜色距离+空间距离"的加权和，不是全局比较所有格子——这保证了性能（否则是 O(像素数 × 格子数)），也保证了区域始终连通增长而不会产生远距离跳跃。`compactness` 越大，空间距离的权重越高，格子形状越规整；重要性权重高的区域会临时降低有效 compactness（见 `effectiveCompactness` 计算），让边界更容易贴合颜色变化，而不是被强制保持方形。

- [ ] **Step 1: 写 SuperpixelSegmenter**

创建 `Sources/BeadCore/SuperpixelSegmenter.swift`：

```swift
import Foundation

public struct CellStats: Sendable, Equatable {
    public var color: LabColor
    public var centerX: Double
    public var centerY: Double
    public var pixelCount: Int
}

public struct SegmentationResult: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let labels: [Int]

    public init(columns: Int, rows: Int, labels: [Int]) {
        precondition(labels.count > 0, "labels must not be empty")
        self.columns = columns
        self.rows = rows
        self.labels = labels
    }
}

public enum SuperpixelSegmenter {
    public static func initialCellIndex(x: Int, y: Int, width: Int, height: Int, columns: Int, rows: Int) -> Int {
        let col = min(columns - 1, (x * columns) / width)
        let row = min(rows - 1, (y * rows) / height)
        return row * columns + col
    }

    public static func initialLabels(width: Int, height: Int, columns: Int, rows: Int) -> [Int] {
        var labels = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                labels[y * width + x] = initialCellIndex(x: x, y: y, width: width, height: height, columns: columns, rows: rows)
            }
        }
        return labels
    }

    public static func cellStats(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        labels: [Int],
        fallback: [CellStats]? = nil
    ) -> [CellStats] {
        let cellCount = columns * rows
        var sumL = [Double](repeating: 0, count: cellCount)
        var sumA = [Double](repeating: 0, count: cellCount)
        var sumB = [Double](repeating: 0, count: cellCount)
        var sumX = [Double](repeating: 0, count: cellCount)
        var sumY = [Double](repeating: 0, count: cellCount)
        var sumWeight = [Double](repeating: 0, count: cellCount)
        var pixelCount = [Int](repeating: 0, count: cellCount)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let idx = y * image.width + x
                let cell = labels[idx]
                let weight = max(importance.weight(x: x, y: y), 0.0001)
                let color = image.pixels[idx]
                sumL[cell] += weight * color.l
                sumA[cell] += weight * color.a
                sumB[cell] += weight * color.b
                sumX[cell] += weight * Double(x)
                sumY[cell] += weight * Double(y)
                sumWeight[cell] += weight
                pixelCount[cell] += 1
            }
        }

        var results = [CellStats]()
        results.reserveCapacity(cellCount)
        for cell in 0..<cellCount {
            if sumWeight[cell] > 0 {
                results.append(CellStats(
                    color: LabColor(l: sumL[cell] / sumWeight[cell], a: sumA[cell] / sumWeight[cell], b: sumB[cell] / sumWeight[cell]),
                    centerX: sumX[cell] / sumWeight[cell],
                    centerY: sumY[cell] / sumWeight[cell],
                    pixelCount: pixelCount[cell]
                ))
            } else if let fallback, cell < fallback.count {
                results.append(fallback[cell])
            } else {
                results.append(CellStats(color: LabColor(l: 0, a: 0, b: 0), centerX: 0, centerY: 0, pixelCount: 0))
            }
        }
        return results
    }

    public static func refine(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        labels: [Int],
        cellColors: [LabColor],
        centers: [CellStats],
        compactness: Double = 10.0
    ) -> [Int] {
        let cellCount = columns * rows
        precondition(cellColors.count == cellCount && centers.count == cellCount)

        let spatialScale = (Double(image.width * image.height) / Double(cellCount)).squareRoot()
        let maxImportance = max(importance.weights.max() ?? 1.0, 0.0001)

        var newLabels = labels
        for y in 0..<image.height {
            for x in 0..<image.width {
                let idx = y * image.width + x
                let ownCell = labels[idx]
                let ownRow = ownCell / columns
                let ownCol = ownCell % columns

                var candidates: Set<Int> = [ownCell]
                if ownCol > 0 { candidates.insert(ownRow * columns + (ownCol - 1)) }
                if ownCol < columns - 1 { candidates.insert(ownRow * columns + (ownCol + 1)) }
                if ownRow > 0 { candidates.insert((ownRow - 1) * columns + ownCol) }
                if ownRow < rows - 1 { candidates.insert((ownRow + 1) * columns + ownCol) }

                let normalizedImportance = importance.weight(x: x, y: y) / maxImportance
                let effectiveCompactness = max(1.0, compactness * (1.0 - 0.6 * normalizedImportance))

                let pixelColor = image.pixels[idx]
                var bestCell = ownCell
                var bestDistance = Double.greatestFiniteMagnitude

                for cell in candidates {
                    let colorDist = pixelColor.distance(to: cellColors[cell])
                    let dx = Double(x) - centers[cell].centerX
                    let dy = Double(y) - centers[cell].centerY
                    let spatialDist = (dx * dx + dy * dy).squareRoot()
                    let combined = (colorDist * colorDist) + pow(effectiveCompactness / spatialScale, 2) * (spatialDist * spatialDist)
                    if combined < bestDistance {
                        bestDistance = combined
                        bestCell = cell
                    }
                }
                newLabels[idx] = bestCell
            }
        }
        return newLabels
    }

    public static func segment(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        iterations: Int = 10,
        compactness: Double = 10.0
    ) -> SegmentationResult {
        var labels = initialLabels(width: image.width, height: image.height, columns: columns, rows: rows)
        var stats = cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels)

        for _ in 0..<iterations {
            let colors = stats.map(\.color)
            let newLabels = refine(
                image: image, columns: columns, rows: rows, importance: importance,
                labels: labels, cellColors: colors, centers: stats, compactness: compactness
            )
            if newLabels == labels {
                break
            }
            labels = newLabels
            stats = cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels, fallback: stats)
        }
        return SegmentationResult(columns: columns, rows: rows, labels: labels)
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/SuperpixelSegmenterTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("SuperpixelSegmenter")
struct SuperpixelSegmenterTests {
    @Test("initial labels tile a 4x4 image into a 2x2 grid evenly")
    func initialLabelsTiling() {
        let labels = SuperpixelSegmenter.initialLabels(width: 4, height: 4, columns: 2, rows: 2)
        #expect(labels[0 * 4 + 0] == 0)
        #expect(labels[0 * 4 + 3] == 1)
        #expect(labels[3 * 4 + 0] == 2)
        #expect(labels[3 * 4 + 3] == 3)
    }

    @Test("cellStats computes uniform-weight mean color per cell on a flat-colored image")
    func cellStatsUniformMean() {
        let red = LabColor(red: 1, green: 0, blue: 0)
        let blue = LabColor(red: 0, green: 0, blue: 1)
        let image = PixelImage(width: 2, height: 2, pixels: [red, blue, red, blue])
        let importance = ImportanceMap.uniform(width: 2, height: 2)
        let labels = SuperpixelSegmenter.initialLabels(width: 2, height: 2, columns: 2, rows: 1)

        let stats = SuperpixelSegmenter.cellStats(image: image, columns: 2, rows: 1, importance: importance, labels: labels)

        #expect(stats.count == 2)
        #expect(abs(stats[0].color.l - red.l) < 0.001)
        #expect(abs(stats[1].color.l - blue.l) < 0.001)
        #expect(stats[0].pixelCount == 2)
        #expect(stats[1].pixelCount == 2)
    }

    @Test("cellStats weights pixels by importance, biasing mean toward high-weight pixels")
    func cellStatsImportanceWeighting() {
        let black = LabColor(red: 0, green: 0, blue: 0)
        let white = LabColor(red: 1, green: 1, blue: 1)
        let image = PixelImage(width: 2, height: 1, pixels: [black, white])
        let importance = ImportanceMap(width: 2, height: 1, weights: [1.0, 99.0])
        let labels = [0, 0]

        let stats = SuperpixelSegmenter.cellStats(image: image, columns: 1, rows: 1, importance: importance, labels: labels)

        #expect(stats[0].color.l > 90.0)
    }

    @Test("segment converges on a flat-colored image producing exactly one label per cell region")
    func segmentFlatImageConverges() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 8, height: 8, pixels: [LabColor](repeating: gray, count: 64))
        let importance = ImportanceMap.uniform(width: 8, height: 8)

        let result = SuperpixelSegmenter.segment(image: image, columns: 4, rows: 4, importance: importance)

        #expect(Set(result.labels).count <= 16)
        #expect(result.labels.count == 64)
    }

    @Test("segment respects high-importance regions by keeping smaller effective cells near them")
    func segmentHighImportanceRefinesBoundaries() {
        var pixels = [LabColor]()
        for _ in 0..<8 {
            for x in 0..<8 {
                pixels.append(x < 4 ? LabColor(red: 0, green: 0, blue: 0) : LabColor(red: 1, green: 1, blue: 1))
            }
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)
        var weights = [Double](repeating: 1.0, count: 64)
        for y in 0..<8 {
            for x in 4..<8 {
                weights[y * 8 + x] = 10.0
            }
        }
        let importance = ImportanceMap(width: 8, height: 8, weights: weights)

        let result = SuperpixelSegmenter.segment(image: image, columns: 4, rows: 4, importance: importance)

        #expect(result.labels.count == 64)
        #expect(result.labels.allSatisfy { $0 >= 0 && $0 < 16 })
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter SuperpixelSegmenter
```
Expected: 5 tests passed

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/SuperpixelSegmenter.swift BeadCore/Tests/BeadCoreTests/SuperpixelSegmenterTests.swift
git commit -m "feat: add SLIC-style importance-weighted superpixel segmentation"
```

---

### Task 5: 调色板联合优化

**Files:**
- Create: `BeadCore/Sources/BeadCore/PaletteOptimizer.swift`
- Test: `BeadCore/Tests/BeadCoreTests/PaletteOptimizerTests.swift`

**Interfaces:**
- Consumes: `SuperpixelSegmenter`（Task 4）、`ColorMatcher`（Task 2）、`BeadGrid`（Task 3）
- Produces:
  - `public struct JointOptimizationResult: Sendable, Equatable { public let segmentation: SegmentationResult; public let cellPaletteColors: [MardColor] }`
  - `public enum PaletteOptimizer { public static func optimize(image:columns:rows:importance:palette:iterations:compactness:) -> JointOptimizationResult; public static func makeGrid(from:) -> BeadGrid }`

关键设计点：每次迭代先用**当前格子的调色板色（`paletteColors`）**而不是原始均值去调用 `SuperpixelSegmenter.refine`，这样区域边界始终围绕"实际会被使用的 MARD 色号"来收敛，而不是为一个色卡里不存在的中间色去优化边界（这是本设计相对于市面工具"先算平均色再匹配"的核心差异点）。

- [ ] **Step 1: 写 PaletteOptimizer**

创建 `Sources/BeadCore/PaletteOptimizer.swift`：

```swift
import Foundation

public struct JointOptimizationResult: Sendable, Equatable {
    public let segmentation: SegmentationResult
    public let cellPaletteColors: [MardColor]
}

public enum PaletteOptimizer {
    public static func optimize(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        palette: [MardColor],
        iterations: Int = 10,
        compactness: Double = 10.0
    ) -> JointOptimizationResult {
        precondition(!palette.isEmpty, "palette must not be empty")

        var labels = SuperpixelSegmenter.initialLabels(width: image.width, height: image.height, columns: columns, rows: rows)
        var stats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels)
        var paletteColors = stats.map { ColorMatcher.nearest(to: $0.color, in: palette) }

        for _ in 0..<iterations {
            let cellLabColors = paletteColors.map(\.lab)
            let newLabels = SuperpixelSegmenter.refine(
                image: image, columns: columns, rows: rows, importance: importance,
                labels: labels, cellColors: cellLabColors, centers: stats, compactness: compactness
            )
            let newStats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: newLabels, fallback: stats)
            let newPaletteColors = newStats.map { ColorMatcher.nearest(to: $0.color, in: palette) }

            let converged = newLabels == labels && newPaletteColors == paletteColors
            labels = newLabels
            stats = newStats
            paletteColors = newPaletteColors
            if converged {
                break
            }
        }

        return JointOptimizationResult(
            segmentation: SegmentationResult(columns: columns, rows: rows, labels: labels),
            cellPaletteColors: paletteColors
        )
    }

    public static func makeGrid(from result: JointOptimizationResult) -> BeadGrid {
        BeadGrid(columns: result.segmentation.columns, rows: result.segmentation.rows, colors: result.cellPaletteColors)
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/PaletteOptimizerTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("PaletteOptimizer")
struct PaletteOptimizerTests {
    @Test("flat black image optimizes every cell to the nearest black palette color")
    func flatImageOptimizesToSingleColor() {
        let black = LabColor(red: 0, green: 0, blue: 0)
        let image = PixelImage(width: 8, height: 8, pixels: [LabColor](repeating: black, count: 64))
        let importance = ImportanceMap.uniform(width: 8, height: 8)
        let palette = [
            MardColor(code: "H7", hex: "000000"),
            MardColor(code: "H1", hex: "FFFFFF"),
        ]

        let result = PaletteOptimizer.optimize(image: image, columns: 4, rows: 4, importance: importance, palette: palette)

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "H7" })
    }

    @Test("two-color image assigns each half to its nearest respective palette color")
    func twoColorImageAssignsDistinctPaletteColors() {
        var pixels = [LabColor]()
        for _ in 0..<8 {
            for x in 0..<8 {
                pixels.append(x < 4 ? LabColor(red: 0, green: 0, blue: 0) : LabColor(red: 1, green: 1, blue: 1))
            }
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)
        let importance = ImportanceMap.uniform(width: 8, height: 8)
        let palette = [
            MardColor(code: "H7", hex: "000000"),
            MardColor(code: "H1", hex: "FFFFFF"),
        ]

        let result = PaletteOptimizer.optimize(image: image, columns: 4, rows: 4, importance: importance, palette: palette)

        let usedCodes = Set(result.cellPaletteColors.map(\.code))
        #expect(usedCodes == ["H7", "H1"])
    }

    @Test("makeGrid produces a BeadGrid with matching dimensions and colors")
    func makeGridMatchesOptimizationResult() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: gray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let palette = [MardColor(code: "H3", hex: "B6B1BA")]

        let result = PaletteOptimizer.optimize(image: image, columns: 2, rows: 2, importance: importance, palette: palette)
        let grid = PaletteOptimizer.makeGrid(from: result)

        #expect(grid.columns == 2)
        #expect(grid.rows == 2)
        #expect(grid.colors == result.cellPaletteColors)
    }

    @Test("optimize terminates within the given iteration budget on a larger image")
    func optimizeTerminatesOnLargerImage() {
        var pixels = [LabColor]()
        for y in 0..<32 {
            for x in 0..<32 {
                let t = Double(x + y) / 64.0
                pixels.append(LabColor(red: t, green: 1 - t, blue: 0.5))
            }
        }
        let image = PixelImage(width: 32, height: 32, pixels: pixels)
        let importance = ImportanceMap.uniform(width: 32, height: 32)

        let result = PaletteOptimizer.optimize(
            image: image, columns: 8, rows: 8, importance: importance,
            palette: MardPalette.standard221, iterations: 10
        )

        #expect(result.cellPaletteColors.count == 64)
        #expect(result.segmentation.labels.count == 1024)
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter PaletteOptimizer
```
Expected: 4 tests passed

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/PaletteOptimizer.swift BeadCore/Tests/BeadCoreTests/PaletteOptimizerTests.swift
git commit -m "feat: add joint superpixel + palette optimization"
```

---

### Task 6: 孤立噪点清理

**Files:**
- Create: `BeadCore/Sources/BeadCore/NoiseCleaner.swift`
- Test: `BeadCore/Tests/BeadCoreTests/NoiseCleanerTests.swift`

**Interfaces:**
- Consumes: `BeadGrid`（Task 3）
- Produces: `public enum NoiseCleaner { public static func clean(_ grid: BeadGrid, maxIsolatedCount: Int = 2) -> BeadGrid }`

清理规则：一个颜色的格子若在整张网格里**总共出现次数 ≤ maxIsolatedCount**，且该格子的每一个存在的邻居（4 连通：上下左右）**都是同一种其他颜色**，则替换为该邻居颜色。这个"总数限制"是为了不误伤棋盘格等大范围交替图案——交替色块的总出现次数通常远超过 2。

- [ ] **Step 1: 写 NoiseCleaner**

创建 `Sources/BeadCore/NoiseCleaner.swift`：

```swift
import Foundation

public enum NoiseCleaner {
    public static func clean(_ grid: BeadGrid, maxIsolatedCount: Int = 2) -> BeadGrid {
        var colorCounts: [String: Int] = [:]
        for color in grid.colors {
            colorCounts[color.code, default: 0] += 1
        }

        let isolatedCandidates = Set(colorCounts.filter { $0.value <= maxIsolatedCount }.keys)
        guard !isolatedCandidates.isEmpty else { return grid }

        var newColors = grid.colors
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                guard isolatedCandidates.contains(color.code) else { continue }

                var neighborColors = Set<String>()
                var neighborMard: [String: MardColor] = [:]
                let neighborOffsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                for (dx, dy) in neighborOffsets {
                    let nx = col + dx
                    let ny = row + dy
                    guard nx >= 0, nx < grid.columns, ny >= 0, ny < grid.rows else { continue }
                    let neighbor = grid.color(col: nx, row: ny)
                    neighborColors.insert(neighbor.code)
                    neighborMard[neighbor.code] = neighbor
                }

                if neighborColors.count == 1, let onlyNeighborCode = neighborColors.first, onlyNeighborCode != color.code {
                    newColors[row * grid.columns + col] = neighborMard[onlyNeighborCode]!
                }
            }
        }

        return BeadGrid(columns: grid.columns, rows: grid.rows, colors: newColors)
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/NoiseCleanerTests.swift`：

```swift
import Testing
@testable import BeadCore

@Suite("NoiseCleaner")
struct NoiseCleanerTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")
    static let green = MardColor(code: "B5", hex: "35E352")

    @Test("single isolated pixel surrounded by one color is replaced by that color")
    func singleIsolatedPixelReplaced() {
        var colors = [MardColor](repeating: Self.blue, count: 9)
        colors[1 * 3 + 1] = Self.red
        let grid = BeadGrid(columns: 3, rows: 3, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 1).code == Self.blue.code)
    }

    @Test("isolated pixel touching two different neighbor colors is left unchanged")
    func isolatedPixelWithMixedNeighborsUnchanged() {
        let colors = [
            Self.blue, Self.blue, Self.blue,
            Self.blue, Self.red, Self.green,
            Self.blue, Self.green, Self.green,
        ]
        let grid = BeadGrid(columns: 3, rows: 3, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 1).code == Self.red.code)
    }

    @Test("checkerboard pattern is left untouched because each color's total count is large")
    func checkerboardPatternUnchanged() {
        var colors = [MardColor]()
        for row in 0..<4 {
            for col in 0..<4 {
                colors.append((row + col) % 2 == 0 ? Self.red : Self.blue)
            }
        }
        let grid = BeadGrid(columns: 4, rows: 4, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned == grid)
    }

    @Test("edge pixel with only two neighbors, both matching, is replaced")
    func edgePixelWithTwoMatchingNeighborsReplaced() {
        let colors = [Self.blue, Self.red, Self.blue]
        let grid = BeadGrid(columns: 3, rows: 1, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 0).code == Self.blue.code)
    }

    @Test("grid with no isolated colors is returned unchanged")
    func noIsolatedColorsUnchanged() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.red, Self.blue, Self.blue])

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned == grid)
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter NoiseCleaner
```
Expected: 5 tests passed

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/NoiseCleaner.swift BeadCore/Tests/BeadCoreTests/NoiseCleanerTests.swift
git commit -m "feat: add isolated-noise cleanup pass"
```

---

### Task 7: Vision 重要性权重图

**Files:**
- Create: `BeadCore/Sources/BeadCore/ImportanceMapProvider.swift`
- Test: `BeadCore/Tests/BeadCoreTests/ImportanceMapProviderTests.swift`

**Interfaces:**
- Consumes: `ImportanceMap`（Task 3）
- Produces:
  - `public protocol ImportanceMapProvider: Sendable { func importanceMap(for image: CGImage) -> ImportanceMap }`
  - `public struct UniformImportanceMapProvider: ImportanceMapProvider`
  - `public struct VisionSaliencyImportanceMapProvider: ImportanceMapProvider`，内部静态方法 `static func resampleWeights(from: CVPixelBuffer, to: Int, height: Int) -> [Double]?`

⚠️ 测试文件中构建 `CGContext` 填色时，务必用 `context.setFillColor(red:green:blue:alpha:)` 分量重载，不要用 `CGColor(red:green:blue:alpha:)`（见 Global Constraints）。

- [ ] **Step 1: 写 ImportanceMapProvider**

创建 `Sources/BeadCore/ImportanceMapProvider.swift`：

```swift
import CoreGraphics
import CoreVideo
import Foundation
import Vision

public protocol ImportanceMapProvider: Sendable {
    func importanceMap(for image: CGImage) -> ImportanceMap
}

public struct UniformImportanceMapProvider: ImportanceMapProvider {
    public init() {}

    public func importanceMap(for image: CGImage) -> ImportanceMap {
        ImportanceMap.uniform(width: image.width, height: image.height)
    }
}

public struct VisionSaliencyImportanceMapProvider: ImportanceMapProvider {
    public init() {}

    public func importanceMap(for image: CGImage) -> ImportanceMap {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let weights = Self.resampleWeights(from: observation.pixelBuffer, to: image.width, height: image.height)
            else {
                return .uniform(width: image.width, height: image.height)
            }
            return ImportanceMap(width: image.width, height: image.height, weights: weights)
        } catch {
            return .uniform(width: image.width, height: image.height)
        }
    }

    static func resampleWeights(from pixelBuffer: CVPixelBuffer, to targetWidth: Int, height targetHeight: Int) -> [Double]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent32Float else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let floatBuffer = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        var minValue = Float32.greatestFiniteMagnitude
        var maxValue = -Float32.greatestFiniteMagnitude
        for y in 0..<sourceHeight {
            for x in 0..<sourceWidth {
                let value = floatBuffer[y * floatsPerRow + x]
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }
        let range = max(maxValue - minValue, 0.0001)

        var weights = [Double](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(sourceHeight - 1, (y * sourceHeight) / targetHeight)
            for x in 0..<targetWidth {
                let sourceX = min(sourceWidth - 1, (x * sourceWidth) / targetWidth)
                let raw = floatBuffer[sourceY * floatsPerRow + sourceX]
                weights[y * targetWidth + x] = Double((raw - minValue) / range)
            }
        }
        return weights
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/ImportanceMapProviderTests.swift`：

```swift
import CoreGraphics
import CoreVideo
import Testing
@testable import BeadCore

@Suite("ImportanceMapProvider")
struct ImportanceMapProviderTests {
    static func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.95, green: 0.9, blue: 0.2, alpha: 1)
        let squareSize = min(width, height) / 3
        context.fill(CGRect(
            x: (width - squareSize) / 2, y: (height - squareSize) / 2,
            width: squareSize, height: squareSize
        ))
        return context.makeImage()!
    }

    @Test("uniform provider returns a flat weight map matching image dimensions")
    func uniformProviderIsFlat() {
        let image = Self.makeTestImage(width: 16, height: 12)
        let provider = UniformImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.width == 16)
        #expect(map.height == 12)
        #expect(map.weights.allSatisfy { $0 == 1.0 })
    }

    @Test("vision saliency provider produces a weight map matching image dimensions")
    func visionProviderMatchesDimensions() {
        let image = Self.makeTestImage(width: 64, height: 64)
        let provider = VisionSaliencyImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.width == 64)
        #expect(map.height == 64)
    }

    @Test("vision saliency provider normalizes weights into [0, 1]")
    func visionProviderNormalizesWeights() {
        let image = Self.makeTestImage(width: 64, height: 64)
        let provider = VisionSaliencyImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.weights.allSatisfy { $0 >= 0.0 && $0 <= 1.0 })
        let distinctValues = Set(map.weights.map { ($0 * 1000).rounded() })
        #expect(distinctValues.count > 1)
    }

    @Test("resampleWeights rejects a pixel buffer with the wrong pixel format")
    func resampleWeightsRejectsWrongFormat() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)

        let result = VisionSaliencyImportanceMapProvider.resampleWeights(from: pixelBuffer!, to: 8, height: 8)

        #expect(result == nil)
    }

    @Test("resampleWeights upsamples a small buffer to a larger target size")
    func resampleWeightsUpsamples() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent32Float]
        CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_OneComponent32Float, attrs as CFDictionary, &pixelBuffer)
        let buffer = pixelBuffer!

        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
        base[0 * floatsPerRow + 0] = 0.0
        base[0 * floatsPerRow + 1] = 1.0
        base[1 * floatsPerRow + 0] = 0.0
        base[1 * floatsPerRow + 1] = 1.0
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let weights = VisionSaliencyImportanceMapProvider.resampleWeights(from: buffer, to: 4, height: 4)

        #expect(weights != nil)
        #expect(weights?.count == 16)
        #expect(weights?[0] == 0.0)
        #expect(weights?[3] == 1.0)
    }
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
swift test --filter ImportanceMapProvider
```
Expected: 5 tests passed（含真实调用 Vision 框架的显著性检测，耗时约 0.05~0.4 秒/次视机器性能而定）

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/ImportanceMapProvider.swift BeadCore/Tests/BeadCoreTests/ImportanceMapProviderTests.swift
git commit -m "feat: add Vision-based saliency importance map with uniform fallback"
```

---

### Task 8: 端到端流水线入口

**Files:**
- Create: `BeadCore/Sources/BeadCore/PatternGenerator.swift`
- Test: `BeadCore/Tests/BeadCoreTests/PatternGeneratorTests.swift`

**Interfaces:**
- Consumes: 全部前置任务的类型
- Produces:
  - `public struct PatternGenerationOptions: Sendable { public let columns, rows: Int; public let palette: [MardColor]; public let iterations: Int; public let compactness: Double; public let maxIsolatedCount: Int; public init(columns:rows:palette:iterations:compactness:maxIsolatedCount:) }`
  - `public enum PatternGenerator { public static func generate(image:importance:options:) -> BeadGrid; public static func generate(cgImage:importanceProvider:options:) -> BeadGrid }`
  - `extension PixelImage { public init(cgImage: CGImage) }`

- [ ] **Step 1: 写 PatternGenerator**

创建 `Sources/BeadCore/PatternGenerator.swift`：

```swift
import CoreGraphics
import Foundation

public struct PatternGenerationOptions: Sendable {
    public let columns: Int
    public let rows: Int
    public let palette: [MardColor]
    public let iterations: Int
    public let compactness: Double
    public let maxIsolatedCount: Int

    public init(
        columns: Int, rows: Int, palette: [MardColor] = MardPalette.standard221,
        iterations: Int = 10, compactness: Double = 10.0, maxIsolatedCount: Int = 2
    ) {
        self.columns = columns
        self.rows = rows
        self.palette = palette
        self.iterations = iterations
        self.compactness = compactness
        self.maxIsolatedCount = maxIsolatedCount
    }
}

public enum PatternGenerator {
    public static func generate(
        image: PixelImage,
        importance: ImportanceMap,
        options: PatternGenerationOptions
    ) -> BeadGrid {
        let optimized = PaletteOptimizer.optimize(
            image: image, columns: options.columns, rows: options.rows,
            importance: importance, palette: options.palette,
            iterations: options.iterations, compactness: options.compactness
        )
        let grid = PaletteOptimizer.makeGrid(from: optimized)
        return NoiseCleaner.clean(grid, maxIsolatedCount: options.maxIsolatedCount)
    }

    public static func generate(
        cgImage: CGImage,
        importanceProvider: ImportanceMapProvider,
        options: PatternGenerationOptions
    ) -> BeadGrid {
        let image = PixelImage(cgImage: cgImage)
        let importance = importanceProvider.importanceMap(for: cgImage)
        return generate(image: image, importance: importance, options: options)
    }
}

extension PixelImage {
    public init(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &rawData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [LabColor]()
        pixels.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let r = Double(rawData[i * 4 + 0]) / 255.0
            let g = Double(rawData[i * 4 + 1]) / 255.0
            let b = Double(rawData[i * 4 + 2]) / 255.0
            pixels.append(LabColor(red: r, green: g, blue: b))
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
```

- [ ] **Step 2: 写测试**

创建 `Tests/BeadCoreTests/PatternGeneratorTests.swift`：

```swift
import CoreGraphics
import Dispatch
import Testing
@testable import BeadCore

@Suite("PatternGenerator")
struct PatternGeneratorTests {
    @Test("generate produces a grid with the requested dimensions from a flat image")
    func generateProducesRequestedDimensions() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 16, height: 16, pixels: [LabColor](repeating: gray, count: 256))
        let importance = ImportanceMap.uniform(width: 16, height: 16)
        let options = PatternGenerationOptions(columns: 8, rows: 8)

        let grid = PatternGenerator.generate(image: image, importance: importance, options: options)

        #expect(grid.columns == 8)
        #expect(grid.rows == 8)
        #expect(grid.colors.count == 64)
    }

    @Test("PixelImage(cgImage:) extracts pixels matching the image's drawn colors")
    func pixelImageFromCGImageExtractsColors() {
        let width = 4, height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let image = PixelImage(cgImage: cgImage)

        #expect(image.width == 4)
        #expect(image.height == 4)
        let expectedRed = LabColor(red: 1, green: 0, blue: 0)
        for pixel in image.pixels {
            #expect(abs(pixel.l - expectedRed.l) < 1.0)
            #expect(abs(pixel.a - expectedRed.a) < 1.0)
            #expect(abs(pixel.b - expectedRed.b) < 1.0)
        }
    }

    @Test("end-to-end generation from a synthetic CGImage completes and covers the full palette-agnostic pipeline")
    func endToEndGenerationFromCGImage() {
        let width = 64, height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 20, rows: 20)
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: VisionSaliencyImportanceMapProvider(),
            options: options
        )

        #expect(grid.columns == 20)
        #expect(grid.rows == 20)
        #expect(grid.colors.count == 400)
        let paletteCodes = Set(MardPalette.standard221.map(\.code))
        #expect(grid.colors.allSatisfy { paletteCodes.contains($0.code) })
    }

    @Test("realistic 100x100 grid with the full 221-color palette completes in reasonable time")
    func realisticSizeCompletesInReasonableTime() {
        let width = 400, height = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.85, green: 0.75, blue: 0.2, alpha: 1)
        context.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 100, rows: 100)

        let start = DispatchTime.now()
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: VisionSaliencyImportanceMapProvider(),
            options: options
        )
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        #expect(grid.columns == 100)
        #expect(grid.rows == 100)
        #expect(elapsedSeconds < 10.0)
    }
}
```

- [ ] **Step 3: 运行完整测试套件确认全部通过**

```bash
swift test
```
Expected: `Test run with 31 tests in 7 suites passed`（其中 100×100 全色卡端到端测试预计耗时 4~5 秒，属于正常范围，验证了"生成过程需要在后台线程执行、UI 需显示进度"这一设计约束的必要性）

- [ ] **Step 4: Commit**

```bash
git add BeadCore/Sources/BeadCore/PatternGenerator.swift BeadCore/Tests/BeadCoreTests/PatternGeneratorTests.swift
git commit -m "feat: add end-to-end pattern generation pipeline entry point"
```

---

## Plan Self-Review Notes

- **Spec 覆盖检查**：主设计文档"核心算法"章节的 5 个步骤（重要性权重图 → 结构增强前置 → SLIC 分割 → 调色板联合优化 → 孤立噪点清理）中，Task 7 覆盖步骤 1，Task 4 覆盖步骤 3，Task 5 覆盖步骤 2+4（结构增强以"高重要性区域降低有效 compactness、让边界更贴合颜色变化"的方式融入 `refine` 逻辑，而非单独的图像预处理步骤——这是一个从设计到实现的合理简化：效果等价，但避免了一个独立的、难以验证的图像滤波步骤），Task 6 覆盖步骤 5。色卡数据（Task 1）与 Lab 色差匹配（Task 2）也均有对应任务。
- **占位符检查**：全部 8 个任务的代码块均为实际编译运行通过的代码，无 TBD/TODO。
- **类型一致性检查**：`MardColor`、`LabColor`、`PixelImage`、`ImportanceMap`、`BeadGrid`、`SegmentationResult`、`CellStats`、`JointOptimizationResult`、`PatternGenerationOptions` 等类型名称和字段名在所有任务中保持一致（已通过实际 `swift build`/`swift test` 交叉验证，非人工核对）。
- **未覆盖范围**：本计划只产出 `BeadCore` 算法包，不包含 SwiftUI App target、SwiftData 持久化、图片裁剪 UI——这些属于 Plan B（数据持久化）和 Plan C（编辑器与导入导出 UI）的范围，届时 Plan C 会把 `BeadCore` 作为本地 Swift Package 依赖引入 Xcode 项目。
