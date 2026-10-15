#!/bin/sh
# Usage: embed-sparkle.sh <bin-dir> <app>
set -eu
FRAMEWORK="$1/Sparkle.framework"
DEST="$2/Contents/Frameworks"
if [ ! -d "$FRAMEWORK" ]; then
    printf 'Missing %s; build the Classwise product first.\n' "$FRAMEWORK" >&2
    exit 1
fi
mkdir -p "$DEST"
rm -rf "$DEST/Sparkle.framework"
# ditto preserves the framework's version symlinks.
ditto "$FRAMEWORK" "$DEST/Sparkle.framework"
# BYE is not sandboxed, so Sparkle's optional XPC services are unnecessary.
rm -rf "$DEST/Sparkle.framework/Versions/B/XPCServices" "$DEST/Sparkle.framework/XPCServices"
