#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Koogo"
BUNDLE_ID="com.revolt.koogo"
MIN_SYSTEM_VERSION="26.0"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SDK_NAME="macosx27.0"

export DEVELOPER_DIR
export MACOSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION"

XCODE_VERSION="$(xcodebuild -version)"
[[ "${XCODE_VERSION%%$'\n'*}" == "Xcode 27."* ]] || {
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

SIGNING_IDENTITY="${SIGNING_IDENTITY:-$("$ROOT_DIR/script/setup_signing.sh")}"

xcrun swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$CONFIGURATION" \
  --sdk "$SDKROOT" \
  -Xlinker -platform_version \
  -Xlinker macos \
  -Xlinker "$MIN_SYSTEM_VERSION" \
  -Xlinker "$SDK_VERSION" \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Frameworks \
  --product "$APP_NAME"

BUILD_DIR="$(xcrun swift build \
  --package-path "$ROOT_DIR" \
  --configuration "$CONFIGURATION" \
  --sdk "$SDKROOT" \
  --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
APP_ICON="$ROOT_DIR/Sources/Koogo/Resources/$APP_NAME.icon"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
ditto "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RESOURCES_DIR/${APP_NAME}_${APP_NAME}.bundle"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
chmod +x "$MACOS_DIR/$APP_NAME"
xcrun actool \
  --compile "$RESOURCES_DIR" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon "$APP_NAME" \
  --standalone-icon-behavior all \
  --output-partial-info-plist "$CONTENTS_DIR/AppIcon.plist" \
  "$APP_ICON"

cat >"$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>$APP_NAME</string>
  <key>CFBundleIconName</key><string>$APP_NAME</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.$BUILD_NUMBER</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key><string>Koogo uses System Events to switch the system between light and dark appearance when you choose the quick action.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUFeedURL</key><string>https://github.com/revolt-mono/koogo/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>2RXhmQRhki0JYXIP9PMcjh1GIsVVIn7Nsae3tHl555M=</string>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
EOF
rm "$CONTENTS_DIR/AppIcon.plist"

codesign \
  --force --options runtime --timestamp=none \
  --entitlements "$ROOT_DIR/script/Koogo.entitlements" \
  --keychain "${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
printf '%s\n' "$APP_BUNDLE"
