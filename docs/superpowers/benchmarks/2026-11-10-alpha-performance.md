# SourceAlphaCells opaque image benchmark — 2026-11-10

## Scope and method

Task 2 only: `SourceAlphaCells.classify(source:columns:rows:)` returns all `nil` after decoding and confirming **every actual RGBA alpha byte is 255**. Transparent images still take the original alpha-extraction and flood-fill path. No use of `CGImageAlphaInfo` to infer opacity. Same `CGImage` / grid per pair; the `old` mode is the frozen pre-change source classification in `SourceAlphaCellsTests.swift`, and `new` invokes production. Input is an in-memory opaque RGBA `CGImage`, not a disk PNG. The 2400×2400 image (5.76 MP) is the realistically larger sample; deliberately no 48 MP image or OOM-prone full-resolution workload. Grid size is `min(imageSide, 150)` square. One unmeasured warm-up followed by five wall-clock measurements in milliseconds. RSS is the isolated test process's peak resident bytes from `getrusage(RUSAGE_SELF)`; its high-water nature and included test/runtime/image allocations mean it is **not** a per-call allocation profile. `rss_after_warmup_bytes` confirms peak may already have been established by warm-up.

Environment: Apple silicon arm64 macOS 26.0, 32 GiB RAM, Apple Swift 6.4.2 / Xcode 27.2, SwiftPM debug build (`swift test --skip-build`). Run once per mode and image size, with identical compiled old/new test code. Reproduce after building with:

```sh
for size in 400 1200 2400; do
  for mode in old new; do
    ALPHA_BENCH_SIZE=$size ALPHA_BENCH_MODE=$mode swift test --skip-build \
      --package-path /Users/jinyuanhui/pd/BeadCore \
      --filter SourceAlphaCellsTests/optInAlphaBenchmark
  done
done
```

| Opaque image | Old five trials (ms) | Old median (ms) | New five trials (ms) | New median (ms) | Median speedup | Old / new peak RSS (MiB) |
|---|---|---:|---|---:|---:|---:|
| 400×400 | 24.149, 24.088, 23.552, 23.977, 24.070 | 24.070 | 4.845, 4.829, 4.797, 4.693, 4.743 | 4.797 | 5.02× | 39.81 / 38.94 |
| 1200×1200 | 194.551, 198.134, 198.287, 196.385, 197.216 | 197.216 | 42.296, 42.707, 42.936, 43.462, 42.739 | 42.739 | 4.61× | 52.02 / 48.72 |
| 2400×2400 | 790.401, 794.152, 821.748, 858.407, 780.541 | 794.152 | 167.824, 169.074, 179.264, 171.803, 171.796 | 171.796 | 4.62× | 93.31 / 81.66 |

Peak RSS bytes, respectively: 41,746,432 / 40,828,928; 54,542,336 / 51,085,312; 97,845,248 / 85,622,784. Warm-up high-water bytes: 41,664,512 / 40,730,624; 54,460,416 / 50,987,008; 97,746,944 / 85,540,864. Timing excludes image construction but includes CoreGraphics decode; peak memory includes test harness, warm-up and source image. The old-path median is consistently well beyond trial noise, so the production change was retained.

## Correctness and validation

- Test-first: `CHECK_ALPHA_FAST_PATH=1 swift test --package-path /Users/jinyuanhui/pd/BeadCore --filter SourceAlphaCellsTests` first produced the expected missing-fast-return failure while source-image equivalence tests passed; after implementation all **10** initial focused tests passed, then the added end-to-end opaque-grid test also passed in the full suite.
- Frozen old source decoder compared **strict `[FixedCell?]` equality** with production on actual alpha-less RGB, opaque RGBA, exterior transparent border plus enclosed H1 hole, edge alpha 128 versus 127, and 11×7 non-divisible source cells including a 15×9 oversized grid. Opaque output is all `nil`; half-transparent and hole classifications match old results. This preserves the old fallback, threshold and cell rounding logic. No PNG file encoding bytes were benchmarked or independently compared; the source-to-grid output and frozen existing golden grids were checked instead.
- `CHECK_ALPHA_FAST_PATH=1 SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path /Users/jinyuanhui/pd/BeadCore`: **168 tests / 24 suites passed**, including all eight existing frozen generation golden grids and the new opaque source-to-end-to-end-grid comparison.
- `SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path /Users/jinyuanhui/pd/BeadPersistence`: **24 tests / 5 suites passed**.
- `xcodebuild -project /Users/jinyuanhui/pd/PerlerBeadApp.xcodeproj -scheme PerlerBeadApp -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED**, one existing AppIntents metadata skipped warning.
- 初次模拟器测试因本地生成的旧 `.xcodeproj` 仍引用先前已撤回的实验文件，构建阶段未执行。重新从 `project.yml` 生成工程后，在旧 iPhone 18 Pro 模拟器上跑出 13/14，其中透明 PNG 保存测试报 `PHPhotosErrorDomain Code=3311`；单项复跑仍失败。只读排查证实该设备的 App PhotosAdd 权限先前已被拒绝（Code 3311 = AccessUserDenied），PNG 像素/透明孔洞断言在写入前已经通过，此失败与不透明快速路径无关。
- 在**新建的独立 iPhone 18 Pro / iOS 27.2 模拟器**中授予相册添加权限，重新运行整个 App/iOS 测试套件，`/tmp/pd-alpha-fresh-ios.xcresult` 记录 **14/14 通过、0 失败**（真实执行数量 14）；没有清空或改动旧模拟器相册资料。
- `git diff --check`: passed.
