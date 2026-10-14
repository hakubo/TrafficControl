#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) TrafficControl.app into ./build using SwiftPM.
#   VERSION=1.2.3   sets CFBundleShortVersionString (default: from Info.plist)
#   BUILD_NUMBER=42 sets CFBundleVersion (default: MAJOR*10000 + MINOR*100 + PATCH of the version,
#                   so 0.1.6 -> 106; monotonic by construction, independent of git history)
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
# CFBundleVersion is what Sparkle compares (sparkle:version), so it must only ever grow. Derive it from the
# marketing version (the release tag, or Info.plist for local builds) rather than the commit count, which a
# rebase or squash can lower. Pre-release suffixes (0.2.0-beta1) are ignored. MINOR and PATCH must stay below 100.
if [ -z "${BUILD_NUMBER:-}" ]; then
    SHORT_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
    IFS=. read -r MAJOR MINOR PATCH <<< "${SHORT_VERSION%%-*}"
    for part in "$MAJOR" "$MINOR" "${PATCH:-0}"; do
        case "$part" in ''|*[!0-9]*) echo "error: can't derive a build number from version '$SHORT_VERSION'" >&2; exit 1 ;; esac
    done
    if [ "$MINOR" -ge 100 ] || [ "${PATCH:-0}" -ge 100 ]; then
        echo "error: MINOR and PATCH must be below 100 to derive a build number ('$SHORT_VERSION')" >&2; exit 1
    fi
    BUILD_NUMBER=$((10#$MAJOR * 10000 + 10#$MINOR * 100 + 10#${PATCH:-0}))
fi
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"

# Ad-hoc signature for local use; scripts/package.sh re-signs with a Developer ID when one is configured.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TrafficControl"))"
