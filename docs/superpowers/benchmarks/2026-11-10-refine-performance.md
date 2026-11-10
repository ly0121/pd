# Refine performance, 2026-11-10

Task 1 decision: **do not retain the production change.** The coefficient-hoisting candidate produced identical labels and golden grids, but a same-process A/B run showed no reliable speedup. `SuperpixelSegmenter.swift` is restored to its original implementation. The new frozen legacy-reference regression test and opt-in benchmark remain.

## Reproduction

Environment: Apple M5, macOS 26.6, Apple Swift 6.4.2, arm64, SwiftPM `-c release`. Commands run with `SWIFT_DETERMINISTIC_HASHING=1`; the benchmark additionally requires `PROFILE_REFINE_BENCHMARKS=1` and is excluded from normal test runs. One unmeasured warm-up precedes five timed samples per case. Times below are wall-clock milliseconds, median of five. Benchmark input: opaque 288×288 synthetic vertical RGB gradient; 48×48 bead grid; `MardPalette.standard221` (221 colors); uniform importance; same CGImage and palette across runs. The local refine input uses initial labels and cell statistics and palette-projected colors. End-to-end calls `PatternGenerator.generate(cgImage:importanceProvider:options:)`.

| Run | Case | Five samples (ms) | Median (ms) |
| --- | --- | --- | ---: |
| Before change | local refine | 15.222, 16.817, 14.957, 16.828, 16.511 | 16.511 |
| Before change | end-to-end | 73.117, 73.532, 74.153, 72.640, 72.041 | 73.117 |
| Candidate change | local refine | 14.652, 14.944, 15.390, 15.016, 15.000 | 15.000 |
| Candidate change | end-to-end | 70.943, 70.849, 70.673, 70.995, 70.546 | 70.849 |
| Same-process A/B, candidate binary | frozen legacy local refine | 14.544, 14.585, 14.470, 14.557, 14.545 | 14.545 |
| Same-process A/B, candidate binary | candidate local refine | 14.613, 14.655, 14.636, 14.648, 14.508 | 14.636 |
| Same-process A/B, candidate binary | candidate end-to-end | 70.441, 72.857, 70.835, 70.869, 70.720 | 70.835 |

The first before/after medians suggested a 1.511 ms (9.2%) local and 2.268 ms (3.1%) end-to-end gain, but runs were sequential and share no control for machine load/thermal variation. In the candidate binary, the frozen old implementation was 0.091 ms faster than the candidate (0.6%), so a meaningful improvement is **not demonstrated**. Reported medians above are observed values, not projections.

## Correctness and revert

Before optimization, new reference cases passed while a temporary source-position assertion failed exactly because the per-pixel coefficient had not yet been hoisted. Golden generation tests passed 8/8. After hoisting, the same-process frozen old implementation matched candidate labels exactly on a tie/edge case (9×7 image, 3×2 grid with coincident centers and identical colors) and mixed-importance non-square cases (37×23/7×4 and 23×37/4×7); seeded generation golden tests passed 8/8. Both candidate and reference retain `Set` candidate traversal, strict `<`, and original floating-point grouping. After the inconclusive performance check, the candidate production edit and its temporary source-position assertion were removed; the regression reference and opt-in benchmark remain for future work. Final post-revert verification: seeded release BeadCore suite 161/161, unsigned iOS Simulator app build succeeded, and `git diff --check` clean.

Run the focused tests with `SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path BeadCore -c release --filter RefineEquivalenceTests` and benchmark with `PROFILE_REFINE_BENCHMARKS=1 SWIFT_DETERMINISTIC_HASHING=1 swift test --package-path BeadCore -c release --filter RefinePerformanceTests`. Do not run the benchmark as part of a normal suite.
