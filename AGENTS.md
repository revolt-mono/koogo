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
- stream telemetry (subsystem `com.revolt.koogo`, categories `app`, `usage`, `quota`) with `script/build_and_run.sh telemetry`.

## repo structure

```
├── Sources/Koogo          menu bar application
│   ├── App                entry point, model lifetimes, scene wiring, preference-change refresh, headless report
│   ├── Shared             leaf primitives: total enum map, persisted value, telemetry, iso 8601 dates, local event monitor, reduce motion helpers, optional presence binding
│   ├── Providers          provider identity (title, symbol, home, agent process, quota capability) and the one owner of order, usage/quota switches, and which quota a card shows, with their settings toggles
│   ├── Panel              menu bar panel shell: toolbar, pager, pager popover, usage page composition, panel-open refresh of usage and quota
│   ├── Settings           settings window shell hosting slice-owned controls
│   ├── Usage              observable snapshot model, pipeline actor (discover, read, parse, dedup, aggregate, name), benchmark
│   │   ├── Events         event identity per provider, record, revision and the one dedup rule, parser contract and quote
│   │   ├── Ingestion      log formats and roots, append-only file reads, parsed logs, event index with the one dedup rule, tally, store with discovery walk and cross-file dedup, ingestion stats
│   │   ├── Providers      the usage source contract and its registry, the json reader the parsers share, and one folder per provider: source (log layout, model names) → parser (token shapes) → pricing; grok joins its history, pi reads a catalog
│   │   ├── Aggregation    period intervals, snapshot builder, and snapshot types
│   │   └── Views          summary, provider cards, chart, formatting
│   ├── Quota              reading and snapshot vocabulary, source contract with its registry and the one failure classification, a read-only model whose `read` is the single busy transition
│   │   ├── Transport      the one tool failure vocabulary, command-line tool runner, line reader, process group lifetime, json-rpc connection
│   │   ├── Providers      per-provider quota sources: codex (app-server client, response decoding, banked reset flow and model), claude (cli stream-json usage request), grok (cli acp billing)
│   │   └── Views          quota section and the codex reset views
│   ├── QuickActions       scan-then-act model, system adapters (appearance, disk images, orphaned agents), and views
│   ├── BreakReminder      countdown state, notifications, controls, and issue alert
│   ├── Inbox              todo rules, persistence with the open summary, and editors
│   ├── Update             sparkle bridge and update indicator
│   └── Resources          bundled image assets
├── Tests/KoogoTests       mirrors the source tree folder for folder and file for file; a fixture lives with the slice that owns its source, and Support holds only slice-free helpers
└── script                 signing, app bundle assembly, launch, and verification
```

## components and ui

- default to swiftui primitives. introduce appkit only when swiftui can't handle the goal cleanly or the glue required outweighs the benefit. don't hand-roll ui components unless explicitly asked.
- use a 4-point grid for structural spacing and padding. use 2-point increments only for compact component internals; keep typography independent from the spacing grid.
