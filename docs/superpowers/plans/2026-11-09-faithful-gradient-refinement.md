# 渐变区域保真改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不抹除原图细节、轮廓与透明格的前提下，减少平滑渐变里的零散异色格与不必要的突兀色带。

**Architecture:** 独立于无损提速；在 `GradientOrderEnforcer` 之后、alpha 强制覆盖之前加入小型后处理器，输入网格、原图每格 Lab 与局部轮廓证据、当前调色板，只接受不会增加该格原图 Lab 色差且能减小与相邻格不合理突变的候选；不能验证更好时不改格。首版仅做保守局部离群色抑制，色带硬跳只能在不损失原图匹配时逐格改善，避免模糊真实纹理。

**Tech Stack:** BeadCore, Swift Testing, CoreGraphics, iOS Simulator screenshots.

**Spec:** `docs/superpowers/specs/2026-11-09-generation-performance-and-gradients-design.md`。必须等无损提速有基准和逐格 golden 验证后再执行本计划，以免把画质变化算成加速效果。

**Files:** Create `BeadCore/Sources/BeadCore/FaithfulGradientRefiner.swift`, `BeadCore/Tests/BeadCoreTests/FaithfulGradientRefinerTests.swift`, `PerlerBeadAppTests/GradientComparisonTests.swift`, `docs/superpowers/benchmarks/2026-11-09-gradient-comparison.md`; modify `BeadCore/Sources/BeadCore/PatternGenerator.swift` only to connect the postprocessor, avoid modifying existing `GradientOrderEnforcer` until old behavior is understood. Keep original `JointOptimizationResult.cellStats` and `ContourDetector` evidence available to refiner; no new persisted field.

### Task 1: 可解释的改色规则与测试

- [ ] **Step 1: 写失败单测。** 设计 `FaithfulGradientRefiner.refine(_ grid: BeadGrid, sourceStats: [CellStats], palette: [MardColor], protected: Set<Int>) -> BeadGrid`。构造 5×1 单色来源 Lab 与网格 `[A,A,B,A,A]`（B 是偏离原图的孤立豆色、A 仍在 palette）期望变为 `[A,A,A,A,A]`；相同网格若 B 更接近原图则保持；构造真实边缘（`sourceStats.contourFraction >= 0.18`）或 `protected` 包含 B 索引则保持；`.empty` 中断邻域，不能跨空洞改色；H1 protected 保持且 H1 不在 palette 时绝不添加。另构造 5×1 平滑原图逐格变亮和候选 `A,B,C`，只有候选既减小突兀跳变又不增加局部原图色差才可替换。
- [ ] **Step 2: RED** `swift test --package-path BeadCore --filter FaithfulGradientRefinerTests` → 类型不存在/期望失败。
- [ ] **Step 3: 最小实现**：只考察所有实际存在的正交邻格颜色相同、该格当前色与邻色不同的局部孤立色（1×N 时最多两个邻格，二维内部最多四个；至少两个有效邻格）；当前格或任何参与判断的邻格是 `.empty` 就跳过；只在当前/邻格轮廓分数 `< 0.18` 且原图 Lab 两侧差异小于候选色之间差异时考虑替换。需 `sourceStats` 长度匹配网格，`protected` 指定透明/固定 H1 格及其紧邻一格（由调用者计算）。使用 `sourceStats[idx].color.distance(to: candidate.lab)` 作为硬门槛：替代色误差 <= 现有色误差（允许浮点等值但不放大误差）。仅从 `palette` 中挑已有邻色；读取原网格做判断、写入新网格，避免遍历顺序产生连锁变化。无明确改进时不动。若 5×1 的 `B` 本就是旧色的真实最优匹配，不强求修改；改色用例应代表现有渐变修正导致离群的实际状态。
- [ ] **Step 4: GREEN** 单元测试，包括高对比纹理格、深色轮廓、背景空格、H1 固定、色表收缩，均不得错改。

### Task 2: 原图与新旧图纸并排验证

- [ ] **Step 1: 建 3 个合成源图测试**：平滑明暗梯度、细深色边线叠加梯度、条纹/斑点真实纹理；调用旧生成路径与 `FaithfulGradientRefiner` 输出各一次。读取 `JointOptimizationResult.cellStats`，对于每个改色格 assert 新色属于 palette、新误差 <= 旧误差、轮廓格/空格没有改动；记录改色坐标、色号及色差。
- [ ] **Step 2: 用真实或用户提供的斑驳样图（如果没有则合成图）分别渲染原图、当前图纸、候选新图并排，在 iOS 模拟器截图/导出；视觉检查是少了离群色还是只是失去原图纹理。用户可视化复核前将后处理置于实验用例，不默认启用。** 如果严格的不增原图色差约束使绝大多数斑驳不能改善，应报告约束冲突与实例，让用户决定是否放宽容差，不能暗中放宽。
- [ ] **Step 3: 仅在真实图／合成图均无明显细节损失并得到用户认可后，修改 `PatternGenerator.generate` 调用后处理器**，把 `sourceStats`、轮廓分数和固定 alpha 掩码提供给它；`NoiseCleaner.clean` 与 `GradientOrderEnforcer.enforce` 顺序保持原样。重新跑所有 package/iOS 用例与性能基准，报告颜色变动数量和时间回归。

### Task 3: 验收和交付

- [ ] 文档记录图像来源、原图/旧图/新图三联截图的实际路径、每格改色统计与均值/高分位原图 Lab 色差，不把“更平滑”作为唯一成功标准；检验项目保存、图例和色号统计同步新结果。
- [ ] `git diff --check`；无可证明改善时保留阶段一无损加速成果，阶段二只提交试验和报告，不修改默认画质。
