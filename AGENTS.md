## engineering

- prefer the simplest end-to-end solution for current requirements. extract shared logic only for real reuse or a shared invariant.
- preserve runtime behavior during formatting, lint, typing, and test-structure changes.

## boundaries

- treat `refs/` as read-only reference material; do not edit or import from that directory.
- remove obsolete paths directly; do not add backward-compatibility layers, fallbacks, or migrations.
- keep public pull requests, commits, generated files, and documentation free of private names, internal context, customer-derived data, and ai attribution.

## toolchain

- use the beta xcode toolchain at `/Applications/Xcode-beta.app` (xcode 27, macos sdk 27, swift 6.4) by pinning `DEVELOPER_DIR`; never default to the stable `Xcode.app`.

## commands

- format: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift format --configuration .swift-format --in-place Package.swift --recursive Sources Tests`
- lint: `swiftlint lint --strict Package.swift Sources Tests`
- test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
- report: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run Koogo --report` (or `script/build_and_run.sh report` for the signed bundle)
- benchmark: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run -c release Koogo --benchmark [home]`
- rendered memory regression (run alone): `KOOGO_MEMORY_TESTS=1 DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter UsageSummaryMemoryTests`

## observability

- verify pipeline behavior with `report` rather than screenshots; its json covers log roots, ingestion counts, the usage snapshot, and typed quota outcomes.
- measure pipeline changes with `benchmark` on the same logs and day: compare retired instructions, which stay stable across runs, and memory across repeated release runs without allocation tracing. the digest stays fixed unless the snapshot is meant to change.
- dropped input stays out of the ui: known-kind lines with unusable fields count in `malformedLines`, events with an unpriced model or billed option list their model in `unpricedModels`, and both log telemetry warnings.
- stream telemetry (subsystem `com.revolt.koogo`, categories `app`, `usage`, `quota`, `activity`) with `script/build_and_run.sh telemetry`.

## repo structure

```
├── Sources/Koogo          menu bar app, one folder per feature slice
│   ├── App                entry point, shared models, headless report
│   ├── Shared             leaf primitives used across slices
│   ├── Providers          provider identity, order, and toggles
│   ├── Panel              menu bar panel shell and pages
│   ├── Settings           settings window
│   ├── Usage              token usage from local logs
│   │   ├── Events         event identity and dedup
│   │   ├── Ingestion      log discovery and reads
│   │   ├── Providers      per-provider parsers and pricing
│   │   ├── Aggregation    snapshot building
│   │   └── Views
│   ├── Quota              provider quota reads
│   │   ├── Transport      cli and json-rpc plumbing
│   │   ├── Providers      per-provider quota sources
│   │   └── Views
│   ├── QuickActions       appearance, disk image, and orphaned agent actions
│   ├── Activity           cpu, memory, gpu, and process load
│   ├── BreakReminder      break countdown and notifications
│   ├── Inbox              todos
│   ├── Update             sparkle updates
│   └── Resources          image assets
├── Tests/KoogoTests       mirrors the source tree; Support holds slice-free helpers
└── script                 signing, bundling, launch, verification
```

## components and ui

- default to swiftui primitives. introduce appkit only when swiftui can't handle the goal cleanly or the glue required outweighs the benefit. don't hand-roll ui components unless explicitly asked.
- use a 4-point grid for structural spacing and padding. use 2-point increments only for compact component internals; keep typography independent from the spacing grid.
