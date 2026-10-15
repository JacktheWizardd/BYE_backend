#!/bin/sh
# Usage: sign-app.sh <app>. Signs ad-hoc unless BYE_SIGN_IDENTITY is set.
set -eu
cd "$(dirname "$0")/.."
. ./scripts/update-config.sh
APP="$1"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    exit 0
fi
# Developer ID: sign nested code inside-out with the hardened runtime.
sign() { codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"; }
if [ -d "$SPARKLE" ]; then
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
    sign "$SPARKLE"
fi
sign "$APP"
codesign --verify --deep --strict "$APP"
spctl -a -vv "$APP" || printf 'Gatekeeper assessment failed (expected before notarization).\n' >&2
