#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) TrafficControl.app into ./build using SwiftPM.
#   VERSION=1.2.3   sets CFBundleShortVersionString (default: from Info.plist)
#   BUILD_NUMBER=42 sets CFBundleVersion (default: git commit count)
#   ARCHS="arm64"   builds only some architectures (default: "arm64 x86_64")
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/TrafficControl.app"
ARCHS="${ARCHS:-arm64 x86_64}"

binaries=()
for arch in $ARCHS; do
    swift build -c release --arch "$arch"
    binaries+=("$(swift build -c release --arch "$arch" --show-bin-path)/TrafficControl")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/TrafficControl"
# Sparkle ships as a universal xcframework; ditto keeps its symlinks intact.
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
    "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "${VERSION#v}" "$PLIST"
fi
plutil -replace CFBundleVersion -string "${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}" "$PLIST"

# Ad-hoc signature for local use; scripts/package.sh re-signs with a Developer ID when one is configured.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TrafficControl"))"
