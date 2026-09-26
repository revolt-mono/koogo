# Koogo repository guide

## Workflow

- Read code and docs relevant to the change; expand only to resolve dependencies or uncertainty.
- Complete the requested outcome, not just a first implementation: check the result and fix failures caused by the change. Match verification to the affected behavior; repeat checks only after changes, failures, or unresolved concerns.
- Continue within the agreed scope without step-by-step approval. Pause for missing access, consequential decisions the request does not settle, or destructive actions not already authorized.

## Engineering

- Prefer the simplest end-to-end solution for current requirements. Extract shared logic only for real reuse or a shared invariant.
- Preserve runtime behavior during formatting, lint, typing, and test-structure changes.

## Boundaries

- Treat `refs/` as read-only reference material; do not edit or import from that directory.
- Remove obsolete paths directly; do not add backward-compatibility layers, fallbacks, or migrations.
- Keep public pull requests, commits, generated files, and documentation free of private names, internal context, customer-derived data, and AI attribution.

## Toolchain

- Use the beta Xcode toolchain at `/Applications/Xcode-beta.app` (Xcode 27, macOS SDK 27, Swift 6.4) by pinning `DEVELOPER_DIR`; never default to the stable Xcode 26.6.

## Commands

- format: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift format --configuration .swift-format --in-place Package.swift --recursive Sources Tests`
- lint: `swiftlint lint --strict Package.swift Sources Tests`
- test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`
- report: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run Koogo --report` (or `script/build_and_run.sh report` for the signed bundle)

## Observability

- `Koogo --report` runs the whole system headlessly and prints JSON: per-provider log roots with existence, tracked file and event counts, unpriced model ids, the full usage snapshot, and the Codex and Grok quota outcomes with typed reasons. Prefer it over screenshots when verifying pipeline behavior.
- Parsing failures are silent by design. Events dropped because a model or one of its billed options has no price surface only as model ids in `unpricedModels` in the report and as telemetry warnings.
- Runtime telemetry logs under subsystem `com.revolt.koogo` (categories `usage`, `quota`); stream it with `script/build_and_run.sh telemetry`.

## Repo structure

Each feature is a vertical slice that owns its rules, state, services, views, and tests; only `App`, `Panel`, and `Settings` compose across features, and every folder may use `Shared`.

```
├── Sources/Koogo          menu bar application
│   ├── App                entry point, model lifetimes and scene wiring, headless report
│   ├── Shared             leaf primitives: telemetry, pager popover, local event monitor, Reduce Motion helpers
│   ├── Panel              menu bar panel shell: toolbar, pager, usage page composition, quota gating
│   ├── Settings           settings window shell hosting slice-owned controls
│   ├── Usage              provider enablement, pipeline service, log locations, and usage vocabulary
│   │   ├── Ingestion      file discovery and admission, incremental reads, event identity and dedup, ingestion stats
│   │   ├── Providers      Codex, Claude, Grok, and Pi Agent formats, identities, and pricing
│   │   ├── Aggregation    calendar periods, snapshots, and summary scope
│   │   └── Views          summary, provider cards, chart, provider toggles
│   ├── Quota              quota state and shared quota views
│   │   ├── Codex          app-server transport, quota and reset flow, views
│   │   └── Grok           billing transport, quota model, views
│   ├── QuickActions       system quick-action adapters and views
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
