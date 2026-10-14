#!/usr/bin/env bash
# Signs dist/TrafficControl.zip and writes dist/appcast.xml, the feed Sparkle checks for updates.
# Run after scripts/package.sh.
#
# The EdDSA private key comes from SPARKLE_PRIVATE_KEY (CI; export it once with
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account TrafficControl -x key.txt)
# or, when that isn't set, from the "TrafficControl" item in the login keychain.
set -euo pipefail

cd "$(dirname "$0")/.."
PLIST="build/TrafficControl.app/Contents/Info.plist"
ZIP="dist/TrafficControl.zip"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
REPO="https://github.com/hakubo/TrafficControl"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
MIN_OS="$(plutil -extract LSMinimumSystemVersion raw "$PLIST")"

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    KEY_FILE="$(mktemp)"
    trap 'rm -f "$KEY_FILE"' EXIT
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
    SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP")"
else
    SIGNATURE="$("$SIGN_UPDATE" --account TrafficControl "$ZIP")"
fi

# This version's CHANGELOG.md section as simple HTML for the update window.
NOTES="$(awk -v v="$VERSION" '/^## /{p = ($2 == v); next} p' CHANGELOG.md | awk '
    /^- /   { if (li) print "</li>"; if (!ul) { print "<ul>"; ul = 1 }; printf "<li>%s", substr($0, 3); li = 1; next }
    /^  +/  { if (li) { sub(/^ +/, ""); printf " %s", $0; next } }
    /^$/    { if (li) { print "</li>"; li = 0 }; if (ul) { print "</ul>"; ul = 0 }; next }
            { if (li) { print "</li>"; li = 0 }; if (ul) { print "</ul>"; ul = 0 }; print "<p>" $0 "</p>" }
    END     { if (li) print "</li>"; if (ul) print "</ul>" }')"

PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TrafficControl</title>
    <link>$REPO</link>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
$NOTES
      ]]></description>
      <enclosure url="$REPO/releases/download/v$VERSION/TrafficControl.zip" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
EOF

echo "Wrote dist/appcast.xml for $VERSION ($BUILD)"
