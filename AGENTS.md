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

## mouse input

- keep the event tap callback free of allocation, locks, lookups, logging, and async work; `ScrollRewriterTests` counts allocations on that path.
- pass continuous and phased scrolling through untouched and drop diagonal or zero wheel events; only make that drop policy stricter.
- add no smoothing, momentum, acceleration, or gesture phases. per-app behavior is the user's line-by-line app list, seeded from installed terminals.

## observability

- verify pipeline behavior with `report` rather than screenshots; its json covers log roots, ingestion counts, the usage snapshot, and typed quota outcomes.
- measure pipeline changes with `benchmark` on the same logs and day: compare retired instructions, which stay stable across runs, and memory across repeated release runs without allocation tracing. the digest stays fixed unless the snapshot is meant to change.
- dropped input stays out of the ui: known-kind lines with unusable fields count in `malformedLines`, events with an unpriced model or billed option list their model in `unpricedModels`, and both log telemetry warnings.
- stream telemetry (subsystem `com.revolt.koogo`, categories `app`, `usage`, `quota`, `activity`, `mouse`) with `script/build_and_run.sh telemetry`.

## repo structure

```
├── Sources/Koogo          menu bar app, one folder per feature slice
│   ├── App                entry point, shared models, headless report
│   ├── Shared             leaf primitives used across slices
│   │   └── PanelUI        panel chrome, scroll, popover, and page placeholders
│   ├── Providers          provider identity, order, and toggles
│   ├── Panel              menu bar panel shell, paging, and the pages that compose several slices
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
│   ├── Mouse              wheel step and button remapping through an event tap
│   ├── BreakReminder      break countdown and notifications
│   ├── KeepAwake          power assertion that keeps the mac awake
│   ├── Inbox              todos
│   ├── Update             sparkle updates
│   └── Resources          image assets
├── Tests/KoogoTests       mirrors the source tree; Support holds slice-free helpers
└── script                 signing, bundling, launch, verification
```

## slices and owners

- `Shared` names no slice; a slice may use `Shared` and nothing from another slice except its models through the environment. a page that shows one slice lives in that slice; a page that composes several lives in `Panel`.
- `AppModels` builds every model from one set of outside dependencies; `KoogoApp` performs the launch effects. each model's doc comment states its lifetime and who starts or refreshes it.
- an outcome the user must still see after the view that started it is gone is model state (`QuotaModel.statuses`, `MouseModel.status`, `BreakReminderModel.issue`); an immediate admission result may be returned.
- user-visible numbers and dates use `Locale.display`: the scene root sets the swiftui locale for `Text(_:format:)`, and a style that renders to a `String` carries the locale itself, built on `Shared/DisplayLocale.swift` or declared in its slice; lint rejects the default-locale entry points.
- adding a provider: add the `Provider` case and follow the compiler through every `switch`, plus a `Usage/Providers` adapter. quota support additionally needs a `QuotaProvider` case, a `QuotaSources` field, and a `Quota/Providers` adapter.

## components and ui

- default to swiftui primitives. introduce appkit only when swiftui can't handle the goal cleanly or the glue required outweighs the benefit. don't hand-roll ui components unless explicitly asked.
- use a 4-point grid for structural spacing and padding. use 2-point increments only for compact component internals; keep typography independent from the spacing grid.
