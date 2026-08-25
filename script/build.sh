#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AgentTracker"
BUNDLE_ID="com.revolt.koogo"
MIN_SYSTEM_VERSION="26.0"
CONFIGURATION="${CONFIGURATION:-debug}"
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
SDK_NAME="macosx27.0"

export DEVELOPER_DIR
export MACOSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION"

[[ "$(xcodebuild -version | head -1)" == "Xcode 27."* ]] || {
  echo "xcode 27 is required at $DEVELOPER_DIR" >&2
  exit 1
}

SDKROOT="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk "$SDK_NAME" --show-sdk-version)"
export SDKROOT

[[ "$SDK_VERSION" == "27."* ]] || {
  echo "macos sdk 27 is required from $DEVELOPER_DIR" >&2
  exit 1
}

case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "CONFIGURATION must be debug or release" >&2; exit 2 ;;
esac

SIGNING_IDENTITY="$("$ROOT_DIR/script/setup_signing.sh")"

xcrun swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$CONFIGURATION" \
  --sdk "$SDKROOT" \
  -Xlinker -platform_version \
  -Xlinker macos \
  -Xlinker "$MIN_SYSTEM_VERSION" \
  -Xlinker "$SDK_VERSION" \
  --product "$APP_NAME"

BUILD_DIR="$(xcrun swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$CONFIGURATION" \
  --sdk "$SDKROOT" \
  --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat >"$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

codesign \
  --force --options runtime --timestamp=none \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
