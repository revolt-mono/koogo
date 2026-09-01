# Koogo repository guide

## Engineering rules

- Choose the simplest correct implementation for current requirements. Only extract shared logic for genuine duplication or when a shared invariant demands the abstraction. Inline one-off/trivial wrappers.
- Build in layers: start from the smallest version that works end to end, then add each capability on top of a working product.
- Keep code self-explanatory. Rewrite unclear logic rather than defending a design with comments.
- Preserve runtime behavior during formatting, lint, typing, and test-structure changes.

## Boundaries

- Treat `refs/` as read-only reference material; do not edit or import from that directory.
- Do not preserve backward compatibility. Remove obsolete paths directly; skip compatibility layers, fallbacks, and migrations.
- Keep public pull requests, commits, generated files, and documentation free of private names, internal context, customer-derived data, and AI attribution.

## Toolchain

- Use the beta Xcode toolchain at `/Applications/Xcode-beta.app` (Xcode 27, macOS SDK 27, Swift 6.4) by pinning `DEVELOPER_DIR`; never default to the stable Xcode 26.6.

## Commands

- format: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift format --configuration .swift-format --in-place Package.swift --recursive Sources Tests`
- lint: `swiftlint lint --strict Package.swift Sources Tests`
- test: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test`

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
