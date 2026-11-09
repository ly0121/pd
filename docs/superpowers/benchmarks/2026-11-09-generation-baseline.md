# Generation baseline — 2026-11-09

Unoptimized checkout `feature/generation-performance-gradients` (`d4c3b31`); Apple M5, macOS 26.6 (25G72), arm64, Swift 6.4.2; local macOS SwiftPM Debug build, not iPhone or Simulator. No production source changes. Run `PROFILE_GENERATION_BENCHMARKS=1 swift test --package-path BeadCore --filter GenerationBenchmarkTests` for end-to-end measurements; `PROFILE_GENERATION_STAGES=1 swift test --package-path BeadCore --filter GenerationBenchmarkTests.stageProfiles` for diagnostics. Both manual timings are opt-in; ordinary `swift test` does not time the generator. Input: fixed CGContext RGB continuous row gradient and opaque colored blocks, 288²→48²/90 colors, 400²→100²/221 colors, 900²→150²/90 colors. `standard221` actually holds 90 colors in this checkout; `allColors` holds 221. Every measurement has one warm-up and five trials, milliseconds, median of sorted five; tests do not enforce a speed threshold. End-to-end runs use uniform importance. Vision is timed separately, not included in total. Profile stage measurements use independently precomputed inputs and are **not additive**, nor do single-iteration internals reflect every optimizer iteration.

| Stage / input | Five trials (ms) | Median (ms) |
|---|---:|---:|
| total 48x48/288x288/90 colors uniform | 1022.42, 1041.83, 1008.39, 1019.87, 1010.65 | 1019.87 |
| total 100x100/400x400/221 colors uniform | 1488.20, 1476.50, 1519.86, 1557.18, 1476.51 | 1488.20 |
| total 150x150/900x900/90 colors uniform | 10083.61, 10107.31, 10215.08, 10182.15, 10075.80 | 10107.31 |
| PixelImage 48x48/288x288/90 colors | 11.90, 12.15, 12.26, 12.14, 12.00 | 12.14 |
| importance uniform 48x48/288x288/90 colors | 0.06, 0.06, 0.06, 0.06, 0.06 | 0.06 |
| importance Vision 48x48/288x288/90 colors | 11.70, 11.37, 10.38, 10.27, 9.79 | 10.38 |
| ContourDetector 48x48/288x288/90 colors | 15.75, 15.93, 15.52, 15.78, 15.61 | 15.75 |
| PaletteOptimizer 48x48/288x288/90 colors | 959.71, 960.17, 964.99, 976.73, 994.86 | 964.99 |
| NoiseCleaner 48x48/288x288/90 colors | 0.26, 0.27, 0.27, 0.27, 0.27 | 0.27 |
| GradientOrderEnforcer 48x48/288x288/90 colors | 1.24, 1.25, 1.23, 1.21, 1.24 | 1.24 |
| SourceAlphaCells 48x48/288x288/90 colors | 11.38, 11.39, 11.24, 11.54, 11.37 | 11.38 |
| optimizer initialLabels 48x48/288x288/90 colors | 6.80, 6.76, 6.58, 6.70, 6.82 | 6.76 |
| optimizer cellStats 48x48/288x288/90 colors | 11.59, 11.96, 12.33, 12.17, 12.20 | 12.17 |
| optimizer nearest 48x48/288x288/90 colors | 23.31, 22.68, 22.79, 23.23, 22.97 | 22.97 |
| optimizer refine 48x48/288x288/90 colors | 58.78, 59.61, 58.49, 59.41, 58.90 | 58.90 |
| PixelImage 100x100/400x400/221 colors | 23.21, 23.32, 22.98, 23.13, 23.32 | 23.21 |
| importance uniform 100x100/400x400/221 colors | 0.11, 0.11, 0.11, 0.11, 0.11 | 0.11 |
| importance Vision 100x100/400x400/221 colors | 16.46, 16.29, 16.62, 17.41, 15.73 | 16.46 |
| ContourDetector 100x100/400x400/221 colors | 30.66, 31.51, 30.93, 30.79, 30.70 | 30.79 |
| PaletteOptimizer 100x100/400x400/221 colors | 1438.34, 1407.76, 1391.64, 1397.69, 1494.27 | 1407.76 |
| NoiseCleaner 100x100/400x400/221 colors | 1.15, 1.21, 1.11, 1.10, 1.10 | 1.11 |
| GradientOrderEnforcer 100x100/400x400/221 colors | 5.26, 5.20, 5.28, 5.63, 5.58 | 5.28 |
| SourceAlphaCells 100x100/400x400/221 colors | 23.57, 22.53, 21.77, 21.60, 22.56 | 22.53 |
| optimizer initialLabels 100x100/400x400/221 colors | 12.50, 12.69, 12.96, 12.39, 12.61 | 12.61 |
| optimizer cellStats 100x100/400x400/221 colors | 22.87, 22.70, 22.75, 22.79, 22.78 | 22.78 |
| optimizer nearest 100x100/400x400/221 colors | 232.68, 235.65, 236.29, 234.17, 235.41 | 235.41 |
| optimizer refine 100x100/400x400/221 colors | 112.77, 112.71, 111.88, 112.19, 111.14 | 112.19 |
| PixelImage 150x150/900x900/90 colors | 116.39, 117.72, 118.63, 120.31, 119.35 | 118.63 |
| importance uniform 150x150/900x900/90 colors | 0.58, 0.56, 0.56, 0.56, 0.57 | 0.56 |
| importance Vision 150x150/900x900/90 colors | 66.13, 67.04, 65.83, 65.93, 65.44 | 65.93 |
| ContourDetector 150x150/900x900/90 colors | 154.54, 154.75, 153.82, 153.56, 179.00 | 154.54 |
| PaletteOptimizer 150x150/900x900/90 colors | 9573.92, 9676.27, 9741.43, 9700.70, 9770.86 | 9700.70 |
| NoiseCleaner 150x150/900x900/90 colors | 2.71, 2.81, 2.77, 2.62, 2.62 | 2.71 |
| GradientOrderEnforcer 150x150/900x900/90 colors | 11.93, 11.98, 12.28, 11.74, 11.34 | 11.93 |
| SourceAlphaCells 150x150/900x900/90 colors | 109.28, 109.65, 111.63, 118.98, 115.60 | 111.63 |
| optimizer initialLabels 150x150/900x900/90 colors | 64.10, 64.24, 64.50, 64.33, 64.36 | 64.33 |
| optimizer cellStats 150x150/900x900/90 colors | 119.00, 118.11, 118.76, 117.10, 116.58 | 118.11 |
| optimizer nearest 150x150/900x900/90 colors | 220.51, 221.16, 221.96, 221.88, 221.05 | 221.16 |
| optimizer refine 150x150/900x900/90 colors | 580.19, 579.28, 581.79, 574.63, 584.52 | 580.19 |

## Interpretation

- 48x48: optimizer median 964.99 ms / total 1019.87 ms (~94.6%); one independent nearest sweep 22.97 ms; one independent refine pass 58.90 ms.
- 100x100: optimizer median 1407.76 ms / total 1488.20 ms (~94.6%); one independent nearest sweep 235.41 ms; one independent refine pass 112.19 ms.
- 150x150: optimizer median 9700.70 ms / total 10107.31 ms (~96.0%); one independent nearest sweep 221.16 ms; one independent refine pass 580.19 ms.
- The independent optimizer probes distinguish initial labels, a single `cellStats` pass, a single nearest sweep, and a single `refine` pass. They do not count iteration passes, early convergence, the exact forced-dark choices, or per-iteration allocation. Use stage-local instrumentation before claiming a per-function share of the full optimizer.
- Vision produced a map without throwing, but the benchmark does not assert whether its weights differ from the uniform fallback. Its standalone median versus uniform isolates provider overhead only; invoking Vision can also change the downstream optimization path and output.
- The two broad-palette smooth-gradient fixtures with `iterations: 0` protect the pre-refinement path. Iterative goldens cover 24×24 four-color RGB blocks through the full `CGImage` entry point with default ten iterations, 24×24 gradient/dark contour with an H1-only palette and default ten iterations, and 32×32 H2/H4 checkerboard. The 12×12 transparent outside/H1-hole grid also has an H1-only candidate fixture. Five independent process runs passed these ordinary goldens. A separate **broad-palette smooth-gradient default-iteration** golden runs only with `SWIFT_DETERMINISTIC_HASHING=1` and passed five independent processes; invoke `SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path BeadCore --filter GenerationEquivalenceTests` for this strict seeded guard. Without the environment variable that one test returns early, so an ordinary test pass alone does not certify broad-palette iterative-gradient equivalence. The existing `SuperpixelSegmenter.refine` uses Set traversal: randomized iteration and a direct-refine tie are documented, but cross-process output variation of the full varied-RGB grid is not established; the early exploratory gradient did show differing outputs between repeated calls. For future changes to `refine`, compare its labels (not just final codes) against the untouched legacy implementation under the same seed before claiming universal losslessness.
- Scope: the seeded broad-palette iterative gradient golden is multicolor and detects palette/refinement changes to this fixed input, while the H1-only iterative grid alone cannot detect many refinement changes. These fixtures do not certify all 24/48-color palettes, portrait/landscape aspect ratios, or varied images using all 221 colors. For any later optimization, add representative cases and compare labels plus final codes before making a universal output-identity claim. No production optimization or gradient behavior change has been made.

## Task 2: invocation-scoped prepared palette, 2026-11-09

Same Apple M5/macOS 26.6/Swift 6.4.2 local Mac SwiftPM Debug setup and opt-in end-to-end benchmark command as above. Uniform importance, no Vision; one warm-up then five measurements per case. The **pre-change** run below was recorded immediately before modifying production sources (independent from the original baseline above); **post-change** uses an invocation-scoped ordered `(MardColor, LabColor, LightnessClass)` cache and its ordered dark subset, leaving the public ColorMatcher API and refinement unchanged. Times in ms.

| Grid / candidate count | Pre-change trials | Pre median | Post-change trials | Post median | Median improvement |
|---|---|---:|---|---:|---:|
| 48x48 / 90 | 1032.89, 1010.52, 1013.81, 1013.75, 1023.38 | 1013.81 | 878.45, 888.12, 885.95, 883.20, 898.18 | 885.95 | 12.6% |
| 100x100 / 221 | 1464.81, 1467.37, 1476.04, 1488.32, 1467.54 | 1467.54 | 980.76, 1005.87, 981.33, 996.69, 1021.63 | 996.69 | 32.1% |
| 150x150 / 90 | 10173.43, 10496.06, 10489.65, 10227.50, 10187.98 | 10227.50 | 8757.59, 8779.95, 8825.65, 9001.13, 9035.88 | 8825.65 | 13.7% |

The original independent-stage baseline put PaletteOptimizer at ~94.6%, ~94.6%, ~96.0% of end-to-end time at 48/100/150; these are **pre-change** stage shares, not post-change estimates. Post-change stage profile was not repeated. Original single-pass `nearest` measured 22.97/235.41/221.16 ms at these sizes; `refine` 58.90/112.19/580.19 ms, but neither probe is additive across iterations. All eight golden grid tests passed with deterministic hashing (including the broad-palette iterative gradient); the ordinary complete suite passed 122/122 after four new tests were added. The new focused comparison matches original `ColorMatcher.nearest` at 1/12/90/221 candidate sizes, first-tie and duplicate behavior, forced-dark subset/fallback; initial optimizer grid colors (including EMPTY), labels, and cellStats are equal to a separately computed legacy path. Iterative equivalence is covered by the goldens. The benchmark only asserts cell counts: **grid identity was verified on golden fixtures, not by storing and comparing the three full benchmark grids before and after**. Existing randomized `Set` traversal in refinement makes independent unseeded benchmark-run grid comparison an unreliable cache regression signal. Neither gradient appearance nor refinement arithmetic/order was changed.

### Task 2 follow-up: full forced-lightness equivalence

Reviewer identified that the first prepared cache only filtered `.dark`, whereas the original matcher also filters explicit `.light`. The final cache now precomputes **both** ordered classes with empty-subset fallback; focused 1/12/90/221-size checks include nil, `.dark`, and `.light`, and a deliberately failing `.light` test was observed before correcting the implementation. A separate varied six-color 40×40 source compares default 10-iteration optimized output against the legacy `ColorMatcher.nearest` refinement path **inside the same process**: labels, final cellStats, and final colors match with `SWIFT_DETERMINISTIC_HASHING=1` across five independent runs. This is a fixed-image seeded comparison, not a proof for every image or unseeded tie order.

After adding the light subset, the opt-in benchmark was repeated in the same Mac Debug setup; each row has one warm-up and five full end-to-end trials (ms). These final timings replace the earlier post-change medians for final-code performance; earlier raw samples above remain an accurate record of the intermediate dark-only version.

| Grid / candidate count | Final-cache five trials (ms) | Final median (ms) | Versus immediate pre-change median |
|---|---|---:|---:|
| 48x48 / 90 | 912.31, 904.67, 886.09, 899.51, 892.54 | 899.51 | 11.3% faster |
| 100x100 / 221 | 964.49, 994.78, 979.49, 971.22, 977.39 | 977.39 | 33.4% faster |
| 150x150 / 90 | 11985.84, 9000.18, 8939.00, 8783.06, 8683.62 | 8939.00 | 12.6% faster; first sample is an outlier |

The existing optional `GenerationBenchmarkTests.stageProfiles` nearest probe (line 127) calls **legacy `ColorMatcher.nearest`**, not `PreparedPalette.nearest`; its original one-pass numbers describe the baseline legacy matcher only and must not be attributed to the optimized hot path. No post-change stage attribution was measured. End-to-end benchmark assertions still check dimensions, not before/after grid code arrays; seeded golden and within-process varied-image comparisons provide the grid-equality evidence instead.
