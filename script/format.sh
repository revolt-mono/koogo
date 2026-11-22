#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

exec swift package --allow-writing-to-package-directory format \
  --exclude refs --exclude dist \
  --swift-format-config .build/checkouts/swift/Sources/AirbnbSwiftFormatTool/airbnb.swiftformat,.swiftformat \
  --swift-lint-config .swiftlint.yml \
  "$@"
