#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
if [ "$BETA_VERSION" = 0.5.1 ]; then exec ./scripts/package-retirement.sh; fi
. ./scripts/update-config.sh
APP="$PWD/dist/$BETA_APP_NAME.app"
DMG="$PWD/dist/BYE-$BETA_VERSION-AppleSilicon.dmg"
ZIP_NAME="BYE-$BETA_VERSION-AppleSilicon.zip"
ZIP="$PWD/dist/$ZIP_NAME"
APPCAST=${BYE_APPCAST:-$PWD/appcast.xml}
notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}
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
if [ -n "$NOTARY_PROFILE" ]; then
    # Notarize and staple the app itself so the update zip carries its ticket.
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notarize.zip"
    notarize "$STAGING/notarize.zip"
    xcrun stapler staple "$APP"
    rm "$STAGING/notarize.zip"
fi
ditto "$APP" "$STAGING/$BETA_APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
sed "s/@BETA_VERSION@/$BETA_VERSION/g" docs/releases/BETA_INSTALLATION.txt > "$STAGING/START HERE.txt"
python3 scripts/check-distribution-privacy.py "$STAGING"
hdiutil create -volname "$BETA_APP_NAME" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"
codesign --verify --strict "$DMG"
if [ -n "$NOTARY_PROFILE" ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "BYE-$BETA_VERSION-AppleSilicon.dmg") > "$DMG.sha256"
# Sparkle update archive: the same signed app, EdDSA-signed for the appcast.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "$ZIP_NAME") > "$ZIP.sha256"
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$UPDATE_KEY_ACCOUNT" "$ZIP")
python3 scripts/make-appcast.py --appcast "$APPCAST" --version "$BETA_VERSION" --build "$BETA_BUILD" \
    --url "$UPDATE_DOWNLOAD_PREFIX/$ZIP_NAME" --signature-output "$SIGNATURE" \
    --notes docs/releases/GITHUB_PRERELEASE.md
printf 'Packaged %s and %s\n' "$DMG" "$ZIP"
