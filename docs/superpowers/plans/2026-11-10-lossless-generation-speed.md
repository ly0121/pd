# 无损生成提速 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task.

**Goal:** 在逐格颜色不变的前提下减少 SLIC 分格和不透明图 alpha 分类耗时/内存。

**Architecture:** 两项彼此独立；第一项只提升 per-pixel candidate loop 不变量位置，不改候选集合顺序与浮点运算；第二项在透明度实际全不透明时提前退出但保持透明图旧流程。先基准与旧实现对照，后小步改动并运行同样基准。无区域合并或画质改动。

**Stack:** Swift 6 / BeadCore Swift Testing / CoreGraphics / iOS XCTest; existing `GenerationEquivalenceTests.swift` & opt-in `GenerationBenchmarkTests.swift`.

**Spec:** `docs/superpowers/specs/2026-11-10-lossless-generation-speed-design.md`。当前已有提交 `5c87f29`；不要变更先前用户已撤回的实验，不提交/推送。

### Task 1: 分格候选循环不变量

**Files:** Modify `BeadCore/Sources/BeadCore/SuperpixelSegmenter.swift`, create `BeadCore/Tests/BeadCoreTests/RefineEquivalenceTests.swift`, create `docs/superpowers/benchmarks/2026-11-10-refine-performance.md`.

- [ ] 写测试内旧实现（从当前 `SuperpixelSegmenter.refine` 保留一份局部等价函数）及平局/边缘/非正方/高低重要性夹杂样图，比较新旧标签；设 `SWIFT_DETERMINISTIC_HASHING=1` 运行同进程对照。用现有 `GenerationEquivalenceTests` 的 8 张黄金图比较最终 grid；基线先 GREEN。
- [ ] 编写同一输入、同一调色板、预热一次五次测量的局部 refine 和完整生成基准，记录运行环境／数据/中位数。现有 `PROFILE_GENERATION_BENCHMARKS=1` 是 Mac 手动性能测试，不纳入普通 suite。
- [ ] 测试先红：临时在候选系数缓存路径断言新值的调用位置／逐候选幂计算次数不同（或可见的等价性 refactor 验证），确认测试不是误测无关逻辑。
- [ ] 在 `SuperpixelSegmenter.refine` 每个像素计算 normalizedImportance/effectiveCompactness 后，只计算一次 `let spatialCoefficient = pow(effectiveCompactness / spatialScale, 2)`；候选内仍计算 `colorDist`, `dx/dy`, `spatialDist` 与原式 `(colorDist*colorDist) + spatialCoefficient*(spatialDist*spatialDist)`，`Set` 遍历与严格 `<` 不动。乘法顺序保持，避免 `.squareRoot()` 替换导致浮点边界变化。
- [ ] 跑相同黄金+旧实现对照+包/iOS 主流程测试、五次中位数。若样本逐格变化或耗时收益小于波动，移除优化并如实报告。

### Task 2: 原图内容不透明快速退出

**Files:** Modify `BeadCore/Sources/BeadCore/SourceAlphaCells.swift`, `BeadCore/Tests/BeadCoreTests/SourceAlphaCellsTests.swift`, create `docs/superpowers/benchmarks/2026-11-10-alpha-performance.md`.

- [ ] 先为 RGB 无 alpha 图、RGBA 全 255 图、全透明外圈+内部孔洞、含 alpha 128 半透明边缘、阈值 127/128 与宽高非整除写源图级对照测试（固定旧实现参考或旧行为黄金）；验证测试失败于缺失的快速路径诊断或预期内存门槛，而非只测试旧已正确行为。
- [ ] 用 CoreGraphics 解到 RGBA 后按字节步长 4 扫 alpha；如全 255 则直接返回 `[FixedCell?](repeating:nil,count:columns*rows)`，**在此之前不分配 alpha 独立数组、connected/queue**。如果发现非 255 则继续原来的 `stride(...).map` + `classify(alpha:...)`；不改样本阈值/连通域顺序/半格规则。检验解码失败仍用旧 nil fallback。
- [ ] 用 400×400、1200×1200 及较大不透明 PNG 样例比较耗时、峰值 RSS/内存分配；混合透明样例与旧实现逐格对照，并确认不透明图 0→0 固定格、PNG 输出不变。
- [ ] 验证 BeadCore、BeadPersistence、iOS App 编译/UI 主流程和 `git diff --check`，文档记录各自结果；保留其它生成步骤/已缓存调色板行为原样。
