#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
APP="$PWD/dist/BYE Apple AI Beta.app"
DMG="$PWD/dist/BYE-$BETA_VERSION-AppleSilicon.dmg"
python3 scripts/check-distribution-privacy.py "$APP"
codesign --verify --deep --strict "$APP"
ACTUAL_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleGetInfoString' "$APP/Contents/Info.plist")
ACTUAL_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
if [ "$ACTUAL_VERSION" != "$BETA_VERSION" ] || [ "$ACTUAL_BUILD" != "$BETA_BUILD" ]; then
    printf 'Build the matching beta version before packaging.\n' >&2
    exit 1
fi
lipo -verify_arch "$BETA_ARCH" "$APP/Contents/MacOS/Classwise"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/bye-beta-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
ditto "$APP" "$STAGING/BYE Apple AI Beta.app"
ln -s /Applications "$STAGING/Applications"
sed "s/@BETA_VERSION@/$BETA_VERSION/g" docs/BETA_INSTALLATION.txt > "$STAGING/START HERE.txt"
python3 scripts/check-distribution-privacy.py "$STAGING"
hdiutil create -volname "BYE Apple AI Beta" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --force --sign - "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "BYE-$BETA_VERSION-AppleSilicon.dmg") > "$DMG.sha256"
printf 'Packaged %s\n' "$DMG"
