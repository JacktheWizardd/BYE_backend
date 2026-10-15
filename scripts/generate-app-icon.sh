#!/bin/sh
# Convert the branding image to the sizes macOS uses in Finder and the Dock.
set -eu
cd "$(dirname "$0")/.."
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/bye-icon.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
ICONSET="$STAGING/AppIcon.iconset"
mkdir -p "$ICONSET"
xcrun swift -module-cache-path "$STAGING/ModuleCache" scripts/render-app-icon.swift \
    assets/branding/AppIcon.png "$STAGING/AppIcon.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$STAGING/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$STAGING/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Sources/Classwise/Resources/AppIcon.icns
printf 'Updated Sources/Classwise/Resources/AppIcon.icns\n'
