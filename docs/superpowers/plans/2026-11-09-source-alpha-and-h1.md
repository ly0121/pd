# 原图透明区与 H1 豆色 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 导入图像的边缘连通透明区不放豆，封闭透明孔洞按当前调色板决定 H1 或留空；新建、调整尺寸均生效。

**Architecture:** BeadCore 以生成使用的原图 CGImage alpha 计算固定格掩码；颜色优化／可选 Vision 后，再覆盖最终网格，避免去噪和渐变改写。UI 在缩图前保留原图用于固定掩码，在新建与重新生成两条路径传递相同规则。

**Tech Stack:** Swift 6、CoreGraphics、Swift Testing、SwiftUI/UIKit、XcodeGen、iOS Simulator。

**Spec:** `docs/superpowers/specs/2026-11-09-source-alpha-and-h1-design.md`。现有工作树包含上一功能未提交代码；不得 reset/覆盖其改动，项目使用 `xcodegen generate`。

---

### Task 1: 从 alpha 得到四邻接透明分类与固定豆格

**Files:** Create `BeadCore/Sources/BeadCore/SourceAlphaCells.swift`, `BeadCore/Tests/BeadCoreTests/SourceAlphaCellsTests.swift`。

- [ ] **Step 1: 写失败测试。** 定义 `enum FixedCell: Equatable { case outside, hole }` 和 `SourceAlphaCells.classify(alpha: [UInt8], width: Int, height: Int, columns: Int, rows: Int) -> [FixedCell?]`。测试：5×5 alpha 四周为 0、中间 3×3 为 255、中心为 0，输出 5×5 对应外圈 `.outside`、中心 `.hole`、其他 nil；无 H1 决策在 Task 2。另测 3×3 透明对角线不连接边缘、四邻接连线连接边缘；用 2×2 原图映射到 1×1（2 外侧／2 不透明）验证 >=50% 的边界以及 1／4 不足时 nil；覆盖宽高非整倍数、完全不透明、全透明和 alpha 127/128 分界。
- [ ] **Step 2: `swift test --package-path BeadCore --filter SourceAlphaCellsTests`，确认类型缺失失败（RED）。**
- [ ] **Step 3: 实现 `SourceAlphaCells.swift`。** `precondition(alpha.count == width * height && width > 0 && height > 0 && columns > 0 && rows > 0)`；从四边全部 `alpha[idx] <= 127` 的像素入队做四邻接 BFS，标记连边种子。目标格 `(c,r)` 覆盖源区间 `x ∈ [(c*width)/columns, ((c+1)*width)/columns)` 与相应 y 区间；当源分辨率小于格数时用目标格中心映射到一个源像素以免空区间。逐格计数边缘连通与封闭透明源像素；`outsideCount * 2 >= total` 优先 `.outside`，否则 `holeCount * 2 >= total` 为 `.hole`，否则 nil；遍历和统计均为 O(width*height+columns*rows)（可预计算按目标格积累频数以避免每格遍历整图）。
- [ ] **Step 4: 测试 GREEN，并补 `CGImage` alpha 提取测试。** 加 `SourceAlphaCells.classify(source: CGImage, columns: Int, rows: Int) -> [FixedCell?]`：CGContext 用 `premultipliedLast | byteOrder32Big` 绘制到 RGBA buffer，读取每第 4 字节；明确 CGImage 的行坐标与网格 row 0 一致（创建 2×2 不对称 alpha CGImage 验证），如有上下颠倒只修转换。完全不透明图快速返回全 nil。运行 `swift test --package-path BeadCore --filter SourceAlphaCellsTests`。
- [ ] **Step 5: 仅在用户要求提交时提交。**

### Task 2: 固定格覆盖生成算法；不改变普通颜色匹配

**Files:** Modify `BeadCore/Sources/BeadCore/PatternGenerator.swift`, `BeadCore/Tests/BeadCoreTests/PatternGeneratorTests.swift`。

- [ ] **Step 1: 先写失败测试。** 用一幅合成 12×12 RGBA（边界透明、中心封闭孔洞），调用 `PatternGenerator.generate(cgImage: ..., importanceProvider: UniformImportanceMapProvider(), options: PatternGenerationOptions(columns: 12, rows: 12, palette: [H1, H7]), foregroundMaskProvider: UniformForegroundMaskProvider(), sourceAlphaImage: sourceCGImage)`；验证外圈 EMPTY，中心 H1；移除 H1 的 palette 仍得中心 EMPTY；小孔洞在 `maxIsolatedCount: 2` 下也不得被 NoiseCleaner 改掉。再用固定全 0 foreground provider 验证 Vision 可以删其他格，但固定 H1 保持；普通不透明图和现有测试结果不变。
- [ ] **Step 2: RED，执行 `swift test --package-path BeadCore --filter PatternGeneratorTests`，期望新参数缺失。**
- [ ] **Step 3: 为 CGImage 重载增可选 `sourceAlphaImage: CGImage? = nil`；先运行既有图像生成获取 grid，再用 `SourceAlphaCells.classify(source: sourceAlphaImage ?? cgImage, columns: options.columns, rows: options.rows)` 生成固定类别。** 取 `options.palette.first(where: { $0.code == "H1" })`；将 `.outside` 写 `.empty`，`.hole` 写 H1 或 `.empty`，其余保留既有输出。覆盖发生在 `NoiseCleaner.clean`/`GradientOrderEnforcer.enforce` 之后，因而不被改写；预处理 RGB 仍沿现有路径，保留不透明格普通调色（有 H1 时自然参与最近色匹配）。
- [ ] **Step 4: GREEN，跑 `swift test --package-path BeadCore`；检查旧 Vision、渐变、无 alpha 情形无回归。**

### Task 3: 新建与调整尺寸路径保留原图 alpha

**Files:** Modify `PerlerBeadApp/NewProjectFlowView.swift`, `PerlerBeadApp/PatternEditorView.swift`; create iOS fixture test `PerlerBeadAppTests/SourceAlphaFlowTests.swift`，按已有 `project.yml` 单测 target 自动收录。

- [ ] **Step 1: 先写失败集成测试**：使用 `UIGraphicsImageRendererFormat.opaque = false` 在 12×12 合成四周透明、中间实色、内部透明洞的 UIImage，先走生成时所用 `NewProjectFlowModel.downsample`，调用 `PatternGenerator.generate(...sourceAlphaImage: original.cgImage)`；验证外圈 EMPTY、内部 H1/无 H1 时 EMPTY；另将 UIImage 用 `pngData` 存取后重新生成不同 grid size，验证相同规则。走真实「生成图纸」UI 按键与「重新生成」用现有样图 UI 测试验证入口未损坏。
- [ ] **Step 2: RED** 用 `xcodegen generate` 与 `xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,id=9A72CAF2-2440-4396-9F9E-7BC8500A9865' -only-testing:PerlerBeadAppTests/SourceAlphaFlowTests CODE_SIGNING_ALLOWED=NO test`，新路径未传原图时测试失败。
- [ ] **Step 3: 连接两条路径。** `NewProjectFlowModel.generate` 现有 downsample 后调用 `PatternGenerator.generate` 加 `sourceAlphaImage: sourceImage.cgImage`；`PatternEditorView.regenerate(columns:palette:)` 后台生成也传入 `sourceAlphaImage: sourceImage.cgImage`。如果源图为非 `.up` 方向，先按 UIImage orientation 归一化再使颜色图像、alpha 图像用同一方向；针对源 `UIImage.scale` 和非正方形验证方向／尺寸。既有 `originalImageData` 用 PNG 保存，确保重新生成能恢复 alpha。不要修改 MardColor.empty、H1 或库存编码。
- [ ] **Step 4: GREEN** 跑 Core 两个包测试、iOS 单测和完整 UI 测试；含 EMPTY 的样图在编辑页白底上无色号，内部 H1 在足够放大时显示 H1；保存相册的 PNG 在外圈格透明、内部 H1 不透明且计入颜色用量。`git diff --check`。

### 验证限制与交付

- [ ] 与 `docs/superpowers/specs/2026-11-09-source-alpha-and-h1-design.md` 的五类验收场景逐一对应，报告真实通过／失败及模拟器 screenshots；如实际颜色算法倾向 H2 而非 H1，不能把「候选 H1」误写成「必选 H1」，只验证 H1 出现在候选集合并对明确纯 H1 输入做精确匹配。
- [ ] 保留已有未提交功能与 `.superpowers/` 临时示意图，未经用户要求不提交、不清理。
