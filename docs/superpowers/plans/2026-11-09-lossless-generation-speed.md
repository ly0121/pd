# 图纸生成无损提速 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 缩短小、中、大图纸的生成时间，保持每格 MARD 色号／EMPTY、默认参数和生成链路完全一致。

**Architecture:** 先以固定输入和阶段耗时确认热点，再将调色板派生属性及迭代不变量在单次生成内预计算；逐项修改、逐项逐格对照并测量，未证明有效或结果不同的改动撤回。保留 SwiftUI 生成流程、Vision、透明区域和 H1 规则。

**Tech Stack:** Swift 6, BeadCore/Swift Testing, XCTest/Simulator, CoreGraphics, Instruments（可选）。

**Spec:** `docs/superpowers/specs/2026-11-09-generation-performance-and-gradients-design.md`

**Files:** `BeadCore/Tests/BeadCoreTests/GenerationEquivalenceTests.swift`（新建，固定输入和逐格黄金结果）；`BeadCore/Tests/BeadCoreTests/GenerationBenchmarkTests.swift`（新建，测量而非 CI 硬阈值）；`BeadCore/Sources/BeadCore/ColorMatcher.swift`（单次生成的候选属性缓存，保留公开 API）；`BeadCore/Sources/BeadCore/PaletteOptimizer.swift`（只调用本次生成候选缓存）；`BeadCore/Sources/BeadCore/SuperpixelSegmenter.swift`（仅在 profiling 确认热点且能等价时修改）；`BeadCore/Sources/BeadCore/PatternGenerator.swift`（可选的阶段计时入口，基准运行之后移除诊断）；`PerlerBeadApp/NewProjectFlowView.swift`（如 profiling 发现 UI/预处理耗时而且能保证一致才修改）。避免更改 `PatternGenerationOptions` 默认值。单独创建 `docs/superpowers/benchmarks/2026-11-09-generation-baseline.md` 保存测量条件和真实数据。

### Task 1: 固定输出基准和阶段耗时

- [ ] **Step 1: 写入逐格基线测试** `GenerationEquivalenceTests.swift`：使用 24×24 确定性 RGB 梯度 + 细暗线、32×32 H2/H4 棋盘、12×12 外圈透明／内部孔洞，并分别用 `standard221`、`allColors`、12 色采样、仅含 H1 的候选集生成。保存当前分支未优化实现的网格代码串（包括 EMPTY）为测试常量；逐格用 `#expect(grid.colors.map(\.code) == expectedCodes)` 验证。新图纸改动前先运行此测试并确认 GREEN；留意候选 Set 顺序如会跨进程影响 tie-break，应先用原实现同输入多次验证基线确定性，不能把不稳定性掩盖成优化误差。
- [ ] **Step 2: 建独立手动 benchmark** `GenerationBenchmarkTests.swift`：针对 48×48（288×288 像素，90 色）、100×100（400×400 像素，221 色）、150×150（900×900 像素，90 色），用固定颜色块 + 连续渐变的 CGContext 图像，直接调用 `PatternGenerator.generate(cgImage:importanceProvider:options:)`，`ContinuousClock` 或 `DispatchTime.now().uptimeNanoseconds` 记耗时；每组先预热再跑 5 次，打印每次和中位数，不把具体秒数设为会在不同机器上误报的 XCTest 断言。提供 `swift test --package-path BeadCore --filter GenerationBenchmarkTests` 独立运行命令。
- [ ] **Step 3: 分阶段 profiling**：先测不含 Vision 的 `UniformImportanceMapProvider` 与真实 Vision provider 的差值；在本地临时计时 `PixelImage(cgImage:)`、importance、ContourDetector、PaletteOptimizer（其中另记初始化、refine、cellStats、nearest）、NoiseCleaner、GradientOrderEnforcer、SourceAlphaCells，固定 48/100/150 尺寸记录 5 次中位数。运行 `swift test --package-path BeadCore --filter GenerationBenchmarkTests`，把结果记入 benchmarks 文档；诊断计时不要永久留在热循环。无可确认性能瓶颈时不要盲改。

### Task 2: 对确认的热点做最小等价优化

- [ ] **Step 1: 测试 RED**：针对目标热点写对应性质/逐格测试（例如重复候选颜色 + 强制深色/无强制候选时 `ColorMatcher.nearest` 与既有实现完全一致，最近距离相等时保留首个候选；`PaletteOptimizer` 逐格颜色和 cellStats/labels 对照）。运行新测试，先验证它能发现预期错误（可局部引入临时错误后还原，而不是把通过测试当成 RED）。
- [ ] **Step 2: 针对当前热点 `ColorMatcher.nearest`**：仅当 Task 1 的计时确认明显占比，创建作用于单次生成的 `PreparedPalette`，初始化按原数组顺序保存 `(MardColor, LabColor, LightnessClass)`，预筛深色候选（空集退回完整列表），单次循环中仍用 `color.distance(to:)`，仍用严格 `<` 判定，保留首个并列色；`ColorMatcher.nearest(to:in:forcedLightness:)` 外部接口及语义不变，在 `PaletteOptimizer.optimize` 创建一次 PreparedPalette 再供所有轮次调用。参考旧实现 `ColorMatcher.swift:93-137`，不要把平方距离、CGFloat 或 SIMD 结果当作严格逐格一致。新增测试覆盖 empty、H1、不同色表大小。
- [ ] **Step 3: 测试 GREEN+量化**：跑 `swift test --package-path BeadCore`，黄金图逐格一致；跑同一 benchmark 记录前后中位数。若收益小于测量噪声则撤销该局部优化。若 `refine` 才是热点，可保留既有 Set 候选遍历顺序，预计算 maxImportance 和每像素计算一次 `pow(effectiveCompactness / spatialScale, 2)` 到候选循环外（原实现同一候选重复计算），分别测试全 grid labels 与最终代码逐格相同；任何复测不同都撤销该小步。不要顺手更换 Set 为数组或调整浮点表达式。
- [ ] **Step 4: 重复 profiling 与单步对照**：只对 Task 1 测得的下一个显著热点重复 RED → 一处修改 → 全量 GREEN → 48/100/150 中位数；停止于收益不足或开始影响结果的边界。

### Task 3: 整体交付核查

- [ ] 在 benchmarks 文档列出原始与优化后每个尺寸/调色板的 5 次数据、中位数与阶段占比，标明 Mac/Simulator、Debug/Release、是否包含 Vision 和预热；不能从包测试推断真实手机耗时。`swift test --package-path BeadCore`、`swift test --package-path BeadPersistence` 和 `xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,id=<available-id>' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test` 分别运行；用 `xcrun xcresulttool get test-results summary --path <result bundle> --format json` 核实执行数量非 0。
- [ ] 审阅 `git diff --check` 与 golden grid；明确报告可量化收益和未优化热点。进入阶段二前不得宣称渐变已改善。
