# 多格短段渐变过渡实验计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task. Steps use checkbox syntax.

**Goal:** 在不改变 App 默认生成的条件下，探索 2–5 格连续色带能否在保留原图细节的约束下改善斑驳与突兀色带，并给出真实三联图和可复现指标。

**Architecture:** 保留已有 PreparedPalette 无损加速及现有生产算法。新增独立实验函数，以旧图纸、原图每格 Lab 统计和当前调色板为输入，从多格连续过渡处提出候选；每一候选均受单格 ΔE76 增量 ≤2.0、整图修改预算 ≤非固定格 1%、真实边缘/纹理及固定格周边保护约束。只在测试 harness 内调用并对比，不在 `PatternGenerator.generate` 中调用，用户看图确认以前绝不默认启用。

**Stack:** BeadCore Swift Testing，CoreGraphics 生成合成 RGB/透明源图，已有 Mac 测试 PNG renderer 和本地 HTML 对比页。

**Existing context:** `BeadCore/Sources/BeadCore/FaithfulGradientRefiner.swift` 是首版孤立格实验，`BeadCore/Tests/BeadCoreTests/FaithfulGradientRefinerTests.swift` 的 `GeneratedGradientComparisonTests` 可重用固定三类输入；`docs/superpowers/benchmarks/2026-11-09-gradient-comparison.md` 与同目录 HTML/PNG 记录首版改色 0。禁止覆盖这些首版图片／数据，新实验用 `2026-11-09-gradient-short-run-*.png` 等新文件名。工作树含尚未提交的缓存加速和首版实验，不重置、不提交、不推送。

---

### Task 1: 可解释的多格候选规则

**Files:** Create `BeadCore/Sources/BeadCore/ShortRunGradientExperiment.swift`, `BeadCore/Tests/BeadCoreTests/ShortRunGradientExperimentTests.swift`.

- [ ] **Step 1: RED tests**：设计 `ShortRunGradientExperiment.propose(_ grid: BeadGrid, sourceStats: [CellStats], palette: [MardColor], protected: Set<Int>, maxErrorIncrease: Double = 2.0, maxChangedFraction: Double = 0.01) -> Result`，Result 包含 candidate grid 和逐格 `Change(index, oldCode, newCode, oldError, newError, reason)`。测试 1×7 与 7×1 的单方向平滑源 Lab 灰阶和 `[A,A,B,B,B,A,A]` 等长度 2–5 色段，可提议至少 1 个沿 source 趋势更顺的 palette 中间色；若当前色表没有中间色，则不变；遍历顺序、并列候选确定。用 40×32 样图验证 cap ≤ floor(1% 非固定格)，低于 100 非固定格时最多一格（沿用首版的非空至少 1 格规则）。
- [ ] **Step 2: NEGATIVE tests**：同色带但原图确实突变时不改；彩色高亮边缘、真实条纹/斑点、暗轮廓、空格、H1、固定格及其一格正交邻格、`pixelCount == 0` 都不改；仅从 palette 选、单格误差增量不超 2.0，左右／上下方向一致，保证旧 grid 不变。三联图用例的 sourceStats 是 SLIC 均值，另以原图固定矩形采样验证细节保护，不把均值低对比当作所有像素都平滑。
- [ ] **Step 3: Verify RED** `swift test --package-path BeadCore --filter ShortRunGradientExperimentTests`：新类型缺失 / 新断言失败；不能把编译不通过的无关原因算 RED。
- [ ] **Step 4: Minimal experiment**：在独立文件实现只读取原网格，沿四邻接同方向分析 2–5 格色段，来源 Lab 连续且相邻差异平缓、`contourFraction < 0.18` 并检查原图矩形区域的亮度/色度变化以区分真实条纹；只把某个格改成原图色差增量 ≤2.0 的调色板色，且能减少该方向比源图更大的豆色相邻跳变，不强求在 palette 不足时平滑。不同候选根据误差增量、跳变改进、调色板顺序作稳定排序，同一格最多改一次；非固定格 1% 预算逐格记录。保持 H1/EMPTY 与已确认保护规则。绝不导入默认生成。
- [ ] **Step 5: GREEN** `swift test --package-path BeadCore --filter ShortRunGradientExperimentTests` 与完整 `swift test --package-path BeadCore`；逐格黄金仍为 8/8 (`SWIFT_DETERMINISTIC_HASHING=1 ... --filter GenerationEquivalenceTests`)。

### Task 2: 生成真实新旧对比与验收数据

**Files:** Modify only experiment harness under `BeadCore/Tests/BeadCoreTests` (create `ShortRunGradientComparisonTests.swift` if necessary), create `docs/superpowers/benchmarks/2026-11-09-gradient-short-run-{smooth,contour,texture}-comparison.png`, `docs/superpowers/benchmarks/2026-11-09-gradient-short-run-comparison.md`, `docs/superpowers/benchmarks/2026-11-09-gradient-short-run-comparison.html`.

- [ ] **Step 1: Reuse same 40×32 deterministic images and baseline pipeline**, including original alpha/H1 classification, as in current `GeneratedGradientComparisonTests`; assert baseline grid matches production output per fixture. Invoke new experiment separately; source|old|candidate panes must use actual render of those grids, not illustration. Do not overwrite existing first-experiment files.
- [ ] **Step 2: For each source print/record** eligible 2–5-cell segments, feasible candidates, actual changed cells, old/new code and ΔE76 per edit, hard-edge length/jump histogram, total changed percentage, average/p95/p99 source error before and after, fixed/H1/EMPTY and one-cell-neighbor diffs (must be 0), palette membership. Explicitly report when candidate still unchanged and distinguish source Lab/SLIC mean from raw source local texture evidence.
- [ ] **Step 3: Visual check**: open each PNG and HTML comparison on desktop and a narrow width where possible; check source/old/new coordinates align. If results show no material improvement, stop at experiment and report limitation, no default integration. If some improvement with no protected detail loss, present actual HTML comparison to user and request visual approval **before** any production change.
- [ ] **Step 4: Run** normal+seeded BeadCore tests, BeadPersistence tests, iOS simulator suite if production paths changed (otherwise earlier iOS 14/14 remains applicable to unchanged default app; don't claim new experiment ran on iOS). `git diff --check` and report true measurements; no commit/push without user request.
