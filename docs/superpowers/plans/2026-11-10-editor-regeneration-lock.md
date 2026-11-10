# 图纸尺寸重生编辑锁定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task.

**Goal:** 重生期间旧网格不可被用户操作重新排队保存，成功重生后持久化与 UI 的新尺寸一致。

**Architecture:** 保持现有同步旧格提交 → 取消待保存 → 后台新格生成 → 持久化新格 → 刷新 UI。以 UI `.disabled` + handler `guard` 双层禁用；不更改生成算法与项目模型。此前 SourceAlphaCells opaque 快速路径继续独立保留。

**Files:** `PerlerBeadApp/PatternEditorView.swift`, `PerlerBeadAppUITests/PerlerBeadAppUITests.swift`; 如单测需要可增加 `PerlerBeadAppTests/EditorRegenerationTests.swift` 测 pure state/saver behavior（勿加生产 mock 接口只为测试）；`PerlerBeadApp/DebouncedGridSaver.swift` 仅在发现取消有缺陷时改。

**Spec:** `docs/superpowers/specs/2026-11-10-editor-regeneration-lock-design.md`。

### Task 1: 重生锁与状态防护

- [ ] **Step 1 RED:** 在现有 UI 流程扩展测试：进入编辑，镜像一次使 `undoButton` enabled；选 24 格、确认重生，验证重生期间 `undoButton`/`redoButton`、画布和工具/色卡、mirror、export 均不可交互。为高耗时检测使用可控测试注入点或较大图；不要依赖后台刚好慢过 UI 查询。另建一步确认 `undoButton` 的实际 handler 在 `isRegenerating` 时无副作用（通过可测试状态代理或 UI 块）。先跑定向 UI 确认禁用断言失败。
- [ ] **Step 2 GREEN:** `PatternEditorView` 画布 `.allowsHitTesting(!isRegenerating)` 或 `.disabled(isRegenerating)`，色卡滚动按钮 `.disabled(isRegenerating)`，toolbar: `undo/redo.disabled(isRegenerating || !canUndo/!canRedo)`, paint/erase/eyedropper tool buttons `.disabled(isRegenerating)`，mirror/regenerate/export 已有禁用保持。`handleCellInteraction`, `undo`, `redo`, `toolButton` action 和色卡 action 都在开头 `guard !isRegenerating`；确认对已开始的拖动事件仍无改格。完成后 `history = GridEditHistory()` 已重置，再开启输入。
- [ ] **Step 3 REGRESSION:** UI test 重生后撤销/重做不可用，退出并重开图纸为新尺寸；若旧格延迟任务尚未保存，等待 >0.6s 后再次重开确保尺寸和网格数据仍是新格。确认空库/原图缺失不启动，保存失败保留旧格。

### Task 2: 全量检查与提交

- [ ] 用受控新模拟器避免相册权限污染：`SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path BeadCore`、`swift test --package-path BeadPersistence`、`xcodegen generate --spec project.yml`，然后 `xcodebuild -project PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -destination 'platform=iOS Simulator,id=<available-id>' -parallel-testing-enabled NO -resultBundlePath <new path> CODE_SIGNING_ALLOWED=NO test`。结果包至少 14 用例 0 失败；若测试因 simulator PhotosAdd 被拒则区分权限与代码，不把 3311 算成功。
- [ ] `git diff --check`、`git status --short`；提交本轮 alpha fast path、既有测试 flaky 修复、editor lock、文档和测试到当前功能分支。按用户要求提交但不推送。
