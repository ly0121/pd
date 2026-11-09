# 渐变区域保真改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不抹除原图细节、轮廓与透明格的前提下，减少平滑渐变里的零散异色格与不必要的突兀色带。

**Architecture:** 独立于无损提速；先做**离线实验函数**而不是接入默认 `PatternGenerator.generate`。输入网格、原图每格 Lab 与局部边缘证据、当前调色板及保护掩码，仅在明确平滑、可减少孤立异色且单格色差增量受限时提出候选；改色和未改色坐标均可追溯。只有用户看过三联图认可后，才另行接入默认流程。不能靠单格严格不增误差来承诺消除最近色量化造成的硬色带。

**Tech Stack:** BeadCore, Swift Testing, CoreGraphics, iOS Simulator screenshots.

**Spec:** `docs/superpowers/specs/2026-11-09-generation-performance-and-gradients-design.md`。必须等无损提速有基准和逐格 golden 验证后再执行本计划，以免把画质变化算成加速效果。

**Files:** Create `BeadCore/Sources/BeadCore/FaithfulGradientRefiner.swift`, `BeadCore/Tests/BeadCoreTests/FaithfulGradientRefinerTests.swift`, `PerlerBeadAppTests/GradientComparisonTests.swift`, `docs/superpowers/benchmarks/2026-11-09-gradient-comparison.md`; modify `BeadCore/Sources/BeadCore/PatternGenerator.swift` only to connect the postprocessor, avoid modifying existing `GradientOrderEnforcer` until old behavior is understood. Keep original `JointOptimizationResult.cellStats` and `ContourDetector` evidence available to refiner; no new persisted field.

### Task 1: 可解释的改色规则与测试

- [ ] **Step 1: 写失败单测。** 设计 `FaithfulGradientRefiner.refine(_ grid: BeadGrid, sourceStats: [CellStats], palette: [MardColor], protected: Set<Int>, maxErrorIncrease: Double = 2.0) -> BeadGrid`。构造 5×1 平滑单色来源 Lab 与人为离群格 `[A,A,B,A,A]`（B 略接近原图、A 仍在 palette 且取代 B 的 Lab ΔE76 增量不大于 2.0）期望变为 `[A,A,A,A,A]`；该用例只验证实验函数的契约，**不是**现有生成器中可达的平滑图样例。替代色增量 >2.0 时保持 B；构造真实彩色边缘（相邻源 Lab 差距明显）、深色轮廓（`contourFraction >= 0.18`）、真实交错纹理或 `protected` 包含 B 时保持；`.empty` 中断邻域、H1 固定及其邻格保持不动。测试受约束的色带个别孤点，而不是期待所有连续双色带都被磨掉。
- [ ] **Step 2: RED** `swift test --package-path BeadCore --filter FaithfulGradientRefinerTests` → 类型不存在/期望失败。
- [ ] **Step 3: 最小实现（仅实验入口）**：只考察所有实际存在的正交邻格颜色相同、该格当前色与邻色不同的局部孤立色（至少两个有效邻格）；当前格或任何参与判断的邻格是 `.empty` 就跳过；检查当前格及邻格 `contourFraction < 0.18` 且它们的来源 Lab 两两距离 <= 4.0，保护彩色高亮度边缘（ContourDetector 主要识别暗边，不足以代替 RGB/Lab 边缘保护）。`sourceStats` 长度必须等于格数且 `pixelCount > 0`；保护 `protected` 指定的透明/固定 H1 格及其**一格正交膨胀邻域**。候选只能是该格正交邻居共同色且在 `palette`；以 `newError - oldError <= maxErrorIncrease`（默认 ΔE76 2.0）为硬上限；实际改色还必须减少与邻格的 Lab 跳变，且修改不超过同图可绘制非固定格数的 1%（稳定按行优先，最多 `floor(0.01 * eligibleCount)`，但非空图至少允许 1 格）。从原网格读、写入新网格，避免连锁修改。无足够证据时不动。记录改色原因和误差差值以支持可视化报告；不接入默认生成链路。
- [ ] **Step 4: GREEN** 单元测试，包括高对比纹理格、深色轮廓、背景空格、H1 固定、色表收缩，均不得错改。

### Task 2: 原图与新旧图纸并排验证

- [ ] **Step 1: 建 3 个合成源图测试**：平滑明暗梯度、细深色边线叠加梯度、条纹/斑点真实纹理；用同一轮优化输出取得原始格、`sourceStats`，仅在测试/实验 harness 上调用 `FaithfulGradientRefiner`，不更改默认 `PatternGenerator.generate`。对每个改色格 assert 新色在 palette、`newError - oldError <= 2.0`、每图改色不超过非固定格的 1%、来源边缘/EMPTY/H1 固定格及其邻格未动；记录改色坐标、原/新色号、ΔE76 差值和邻域差值。检查全图误差均值及 p95/p99，若明显恶化则拒绝该候选。
- [ ] **Step 2: 用真实或用户提供的斑驳样图（如果没有则合成图）分别渲染原图、当前图纸、候选新图并排，在 iOS 模拟器截图/导出；视觉检查是否减少真正的异色斑而没有失去纹理。对普通图纸统计可评估的孤立色数量、符合上限的候选、实际改色数量和连续色带的保留比例；若零/极少符合条件，明示严格保护条件和结果，不能宣称已改善硬色带。用户验收前保持实验入口，不默认启用。**
- [ ] **Step 3: 仅在真实图／合成图均无明显细节损失并得到用户另行认可后，才考虑修改 `PatternGenerator.generate` 调用后处理器**，把 `sourceStats`、原图 Lab 邻域证据和固定 alpha 掩码传入；在 CGImage 层已完成固定格分类后保护外圈/孔洞及其一格邻域。`NoiseCleaner.clean` 与 `GradientOrderEnforcer.enforce` 顺序保持原样。此阶段的实验交付不包括默认启用；若无认可则维持现有生产生成结果。启用时必须重新跑所有 package/iOS 用例与性能基准，报告变动格数和时间回归。

### Task 3: 验收和交付

- [ ] 文档记录图像来源、原图/旧图/新图三联截图的实际路径、每格改色统计与均值/高分位原图 Lab 色差，不把“更平滑”作为唯一成功标准；检验项目保存、图例和色号统计同步新结果。
- [ ] `git diff --check`；无可证明改善时保留阶段一无损加速成果，阶段二只提交试验和报告，不修改默认画质。
