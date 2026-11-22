## principles and boundaries

- follow the airbnb swift style guide (https://github.com/airbnb/swift), including rules the formatter cannot enforce, without `// MARK:` comments.
- treat `refs/` as read-only; never edit or import from that directory.
- remove obsolete paths directly; add no compatibility layers, fallbacks, or migrations.
- keep public pull requests, commits, generated files, and docs free of private names, internal context, customer data, and ai attribution.

## commands

pin `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` for all `swift` commands; never use `Xcode.app`.

- format / lint: `script/format.sh [--lint]`
- test: `swift test`
- memory regressions: `KOOGO_MEMORY_TESTS=1 swift test --filter UsageSummaryMemoryTests` (run alone); `KOOGO_MEMORY_TESTS=1 swift test --filter 'LogStoreMemoryTests|UsageEventIndexMemoryTests'`
- report: `swift run Koogo --report` (signed bundle: `script/build_and_run.sh report`)
- benchmark: `swift run -c release Koogo --benchmark [home]`
- telemetry: `script/build_and_run.sh telemetry`

## architecture and ui

- slices under `Sources/Koogo` depend only on `Shared` and other slices' models via environment. multi-slice pages live in `Panel`; `Settings` lays out slice controls.
- model init has no launch effects; `KoogoApp` starts models. document lifetime and starter on each model.
- outcomes that must outlive the view that started them are model state, not return values.
- default to swiftui primitives. use appkit only when swiftui cannot handle the goal cleanly, and do not hand-roll ui components unless asked.
- use a 4pt grid for structural spacing and padding, 2pt increments only for compact internals, and keep typography independent of the grid.

## tests

- run tests that read process-wide state (cpu time, allocations) in exit tests; nest memory suites under `MemoryMeasurement`.
- use `Scratch` for temp directories and defaults, and `TestExecutable` for mock provider scripts.

## mouse input

- keep the event tap callback free of allocation, locks, lookups, logging, and async work.
- pass continuous and phased scrolling through untouched; drop diagonal or zero wheel events (only make drops stricter).
- add no smoothing, momentum, acceleration, gesture phases, or per-app overrides beyond the user's line-by-line app list.

## observability

- verify pipeline behavior with `--report` rather than screenshots.
- benchmark pipeline changes on the same logs and day using retired instructions and repeated release runs (no allocation tracing). keep the digest fixed unless the snapshot should change.
- measure app footprint on the bundle opened via launch services, not a direct binary, so `LSEnvironment` enables the space-efficient allocator.
- keep dropped input out of the ui: count known-kind lines with unusable parsed fields in `malformedLines`, list unpriced models or billed options in `unpricedModels`, and log telemetry warnings for both.
