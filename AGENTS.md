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

- `Koogo --report` runs the whole system headlessly and prints JSON: per-provider log roots with existence, tracked file and event counts, unpriced model ids, the full usage snapshot, and the Codex quota outcome with a typed reason. Prefer it over screenshots when verifying pipeline behavior.
- Parsing failures are silent by design; events dropped for missing pricing surface only as `unpricedModels` in the report and as telemetry warnings.
- Runtime telemetry logs under subsystem `com.revolt.koogo` (categories `usage`, `quota`); stream it with `script/build_and_run.sh telemetry`.

## Repo structure

```
├── Sources/Koogo       menu bar application
│   ├── App             lifecycle and feature-owned observable state
│   │   ├── BreakReminder
│   │   ├── Inbox
│   │   ├── Quota
│   │   ├── Update
│   │   └── Usage
│   ├── QuickActions    system quick-action adapters
│   ├── Quota           Codex quota transport, session, and service
│   ├── Usage           usage records and service orchestration
│   │   ├── Aggregation calendar-based snapshots and summaries
│   │   ├── Ingestion   incremental log reading, parsing, and event indexing
│   │   └── Providers   Claude, Codex, and Pi Agent adapters and pricing
│   ├── Views           feature-owned SwiftUI panels and controls
│   └── Resources       bundled image assets
├── Tests/KoogoTests    feature-aligned behavior tests and shared fixtures
└── script              signing, app bundle assembly, launch, and verification
```

## Components and UI

- Default to SwiftUI primitives. Introduce AppKit only when SwiftUI can't handle the goal cleanly or the glue required outweighs the benefit. Don't hand-roll UI components unless explicitly asked.
- Use a 4-point grid for structural spacing and padding. Use 2-point increments only for compact component internals; keep typography independent from the spacing grid.
