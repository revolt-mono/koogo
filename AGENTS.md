## repository rules

- follow [airbnb swift style](https://github.com/airbnb/swift), including rules beyond formatter coverage. no `// MARK:` comments.
- treat `refs/` as read-only; never edit or import from that directory.
- remove obsolete paths directly; add no compatibility layers, fallbacks, or migrations.
- keep public pull requests, commits, generated files, and docs free of private names, internal context, customer data, and ai attribution.

## commands

all `swift` commands require `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. never use `Xcode.app`.

- format/lint: `script/format.sh [--lint]`
- test: `swift test`
- memory regressions: `KOOGO_MEMORY_TESTS=1 swift test --filter UsageSummaryMemoryTests` (run alone); `KOOGO_MEMORY_TESTS=1 swift test --filter 'LogStoreMemoryTests|UsageEventIndexMemoryTests'`
- report: `swift run Koogo --report` (signed bundle: `script/build_and_run.sh report`)
- benchmark: `swift run -c release Koogo --benchmark [home]`
- telemetry: `script/build_and_run.sh telemetry`

## architecture and ui

- `Sources/Koogo` slice dependencies: only `Shared` and other slices' models via environment. multi-slice pages in `Panel`; slice control layout in `Settings`.
- `KoogoApp` starts models; no launch effects in init. document lifetime and starter on each model.
- outcomes that must outlive their initiating view belong in model state, not return values.
- default to swiftui primitives. appkit only when swiftui lacks a clean solution. hand-roll ui components only on request.
- structural spacing and padding: 4pt grid. 2pt increments only for compact internals. typography independent of grid.

## tests

- use exit tests for process-wide state reads (cpu time, allocations). nest memory suites under `MemoryMeasurement`.
- `Scratch` for temp directories and defaults; `TestExecutable` for mock provider scripts.

## mouse input

- event tap callback: no allocations, locks, lookups, logging, or async work.
- pass continuous and phased scrolling unchanged. drop diagonal or zero wheel events; only tighten drop rules.
- no smoothing, momentum, acceleration, or gesture phases. per-app overrides limited to user's line-by-line app list.

## observability

- verify pipeline behavior with `--report`, not screenshots.
- benchmark pipeline changes: same logs and day, repeated release runs, retired instructions, no allocation tracing. keep digest fixed unless snapshot should change.
- app footprint: launch bundle via launch services, not binary directly, so `LSEnvironment` enables the space-efficient allocator.
- keep dropped input out of ui. `malformedLines` counts known-kind lines with unusable parsed fields. `unpricedModels` lists unpriced models or billed options. log telemetry warnings for both.
