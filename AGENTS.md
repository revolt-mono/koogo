## Engineering

- Prefer the simplest end-to-end solution for current requirements. Extract shared logic only for real reuse or a shared invariant.
- Preserve runtime behavior during formatting, lint, typing, and test-structure changes.

## Boundaries

- Treat `refs/` as read-only reference material; do not edit or import from that directory.
- Remove obsolete paths directly; do not add backward-compatibility layers, fallbacks, or migrations.
- Keep public pull requests, commits, generated files, and documentation free of private names, internal context, customer-derived data, and AI attribution.

## Toolchain

- Use the beta Xcode toolchain at `/Applications/Xcode-beta.app` (Xcode 27, macOS SDK 27, Swift 6.4) by pinning `DEVELOPER_DIR`; never default to the stable `Xcode.app`.

## Commands

- format: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift format --configuration .swift-format --in-place Package.swift --recursive Sources Tests`
- lint: `swiftlint lint --strict Package.swift Sources Tests`
- test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
- report: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run Koogo --report` (or `script/build_and_run.sh report` for the signed bundle)
- benchmark: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run -c release Koogo --benchmark [home]`
- rendered memory regression (run alone): `KOOGO_MEMORY_TESTS=1 DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter UsageSummaryMemoryTests`

## Observability

- Verify pipeline behavior with `report` rather than screenshots; its JSON covers log roots, ingestion counts, the usage snapshot, and typed quota outcomes.
- Measure pipeline changes with `benchmark` on the same logs and day: compare retired instructions, which stay stable across runs, and memory across repeated release runs without allocation tracing. The digest stays fixed unless the snapshot is meant to change.
- Dropped input stays out of the UI: known-kind lines with unusable fields count in `malformedLines`, events with an unpriced model or billed option list their model in `unpricedModels`, and both log telemetry warnings.
- Stream telemetry (subsystem `com.revolt.koogo`, categories `app`, `usage`, `quota`) with `script/build_and_run.sh telemetry`.

## Repo structure

Each feature is a vertical slice that owns its rules, state, services, views, and tests; only `App`, `Panel`, and `Settings` compose across features, every slice may use `Shared` and `Providers`, and `Usage` and `Quota` are engines that take their provider set from the caller.

```
├── Sources/Koogo          menu bar application
│   ├── App                entry point, model lifetimes and scene wiring, headless report and benchmark
│   ├── Shared             leaf primitives: total enum map, persisted value, telemetry, ISO 8601 dates, pager popover, local event monitor, Reduce Motion helpers, optional presence binding
│   ├── Providers          provider identity (title, symbol, home path, quota capability) and the one owner of order and usage/quota switches, with their settings toggles
│   ├── Panel              menu bar panel shell: toolbar, pager, usage page composition, panel-open refresh of usage and quota
│   ├── Settings           settings window shell hosting slice-owned controls; refreshes models when provider switches change
│   ├── Usage              pipeline actor (discover, read, parse, dedup, aggregate, name) and the observable snapshot model
│   │   ├── Model          event identity per provider, record, revision and the one dedup rule, parser contract
│   │   ├── Ingestion      append-only file reads, parsed logs, event index, discovery walk, log store with cross-file dedup, ingestion stats
│   │   ├── Providers      per-provider log layout and parsers: Codex, Claude, Grok (session with history join), and Pi Agent (catalog), plus pricing tables
│   │   ├── Aggregation    calendar periods, snapshot builder, snapshot types, model display names
│   │   └── Views          summary, provider cards, chart, formatting
│   ├── Quota              reading and status vocabulary, source contract, one model for fetch state and the Codex banked reset flow, section views
│   │   ├── Transport      command-line tool runner and JSON-RPC connection
│   │   ├── Codex          app-server client, quota source and response decoding, reset attempt and outcome types, reset views
│   │   ├── Claude         local CLI stream-json usage request as a quota source
│   │   └── Grok           local CLI ACP billing as a quota source
│   ├── QuickActions       scan-then-act model, system adapters (appearance, disk images, orphaned agents), and views
│   ├── BreakReminder      countdown state, notifications, controls, and issue alert
│   ├── Inbox              todo rules, persistence, and editors
│   ├── Update             Sparkle bridge and update indicator
│   └── Resources          bundled image assets
├── Tests/KoogoTests       slice-aligned behavior tests; Support holds shared test helpers
└── script                 signing, app bundle assembly, launch, and verification
```

## Components and UI

- Default to SwiftUI primitives. Introduce AppKit only when SwiftUI can't handle the goal cleanly or the glue required outweighs the benefit. Don't hand-roll UI components unless explicitly asked.
- Use a 4-point grid for structural spacing and padding. Use 2-point increments only for compact component internals; keep typography independent from the spacing grid.
