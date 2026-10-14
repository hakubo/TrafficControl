#!/usr/bin/env bash
# Builds the app and packages it as dist/TrafficControl.dmg and dist/TrafficControl.zip.
#
# Without credentials the app is ad-hoc signed: it runs, but macOS warns on first launch.
# To sign and notarize, set:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)" (must be in the keychain)
#   NOTARY_PROFILE  a keychain profile created with `xcrun notarytool store-credentials`
#     or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD (an app-specific password)
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

APP="build/TrafficControl.app"
DIST="dist"
rm -rf "$DIST"
mkdir -p "$DIST"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements Resources/TrafficControl.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
fi

notarize() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" --wait
    fi
}
can_notarize() {
    [ -n "${SIGN_IDENTITY:-}" ] && { [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${APPLE_ID:-}" ]; }
}

if can_notarize; then
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    notarize "$DIST/notarize.zip"
    rm "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
fi

# Zip: for people who prefer it, and for Homebrew-style installs.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/TrafficControl.zip"

# DMG with the usual drag-to-Applications layout.
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "TrafficControl" -srcfolder "$STAGING" -ov -format UDZO "$DIST/TrafficControl.dmg"
rm -rf "$STAGING"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/TrafficControl.dmg"
    if can_notarize; then
        notarize "$DIST/TrafficControl.dmg"
        xcrun stapler staple "$DIST/TrafficControl.dmg"
    fi
fi

(cd "$DIST" && shasum -a 256 TrafficControl.dmg TrafficControl.zip > SHA256SUMS.txt)
echo "Packaged:"
ls -lh "$DIST"
