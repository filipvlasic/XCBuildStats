#!/usr/bin/env bash
#
# Builds XCBuildStats.app and packages a drag-to-Applications DMG.
#
# Notarized (recommended, "just works" for everyone) — needs a Developer ID cert:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#   (requires a one-time: xcrun notarytool store-credentials XCBS_NOTARY ... — see DISTRIBUTION.md)
#
# Unsigned stopgap (works today, but users must clear quarantine once):
#   ./scripts/release.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="XCBuildStats"
CONFIG="Release"
BUILD_DIR=".xcodebuild"
APP="$BUILD_DIR/Build/Products/$CONFIG/$SCHEME.app"
DIST="dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-XCBS_NOTARY}"
DEV_ID="${DEV_ID:-}"

# Point xcodebuild at Xcode if xcode-select is on CommandLineTools.
if [ -z "${DEVELOPER_DIR:-}" ] && xcode-select -p 2>/dev/null | grep -q "CommandLineTools"; then
  XC="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)"
  [ -n "$XC" ] && export DEVELOPER_DIR="$XC/Contents/Developer"
fi

command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null

echo "==> Building $SCHEME ($CONFIG)"
if [ -n "$DEV_ID" ]; then
  xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEV_ID" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    clean build >/dev/null
else
  xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" clean build >/dev/null
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0")"
DMG="$DIST/$SCHEME-$VERSION.dmg"

echo "==> Packaging DMG (v$VERSION)"
rm -rf "$DIST"; mkdir -p "$DIST"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$SCHEME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "$DEV_ID" ]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$DEV_ID" "$DMG"
  echo "==> Notarizing (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  echo "✅ Notarized DMG ready: $DMG"
else
  echo "⚠️  Built WITHOUT Developer ID / notarization."
  echo "   The DMG works, but after downloading, the first launch is blocked by Gatekeeper."
  echo "   Users clear it once with either:"
  echo "     • right-click the app in /Applications → Open, or"
  echo "     • xattr -dr com.apple.quarantine /Applications/$SCHEME.app"
  echo "✅ Unsigned DMG ready: $DMG"
fi

echo ""
echo "To publish v$VERSION:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  then attach $DMG to the GitHub release for tag v$VERSION"
