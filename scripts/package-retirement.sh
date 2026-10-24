#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
. ./scripts/update-config.sh
OUTPUT="$PWD/dist/retirement"
APP="$OUTPUT/$BETA_APP_NAME.app"
ZIP="$OUTPUT/BYE-$BETA_VERSION-AppleSilicon.zip"
DMG="$OUTPUT/BYE-$BETA_VERSION-AppleSilicon.dmg"
[ ! -e "$ZIP" ] && [ ! -e "$DMG" ] || { echo 'Refusing to overwrite retirement artifacts.' >&2; exit 1; }
python3 scripts/retirement/verify-mac.py "$APP"
python3 scripts/check-distribution-privacy.py "$APP"
STAGING=$(mktemp -d "$OUTPUT/.package-XXXXXX")
ditto "$APP" "$STAGING/$BETA_APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
printf 'BYE 0.5.1 retirement\nSearch, ratings, reviews and account features have been removed. Only application updates remain.\nSaved data outside the app is preserved.\nThis build is ad-hoc signed and not notarized.\n' > "$STAGING/START HERE.txt"
hdiutil create -volname "$BETA_APP_NAME" -srcfolder "$STAGING" -format UDZO "$DMG"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"
hdiutil verify "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$OUTPUT" && shasum -a 256 "BYE-$BETA_VERSION-AppleSilicon.zip" "BYE-$BETA_VERSION-AppleSilicon.dmg") > "$OUTPUT/SHA256SUMS"
(cd "$OUTPUT" && shasum -a 256 "BYE-$BETA_VERSION-AppleSilicon.zip") > "$ZIP.sha256"
(cd "$OUTPUT" && shasum -a 256 "BYE-$BETA_VERSION-AppleSilicon.dmg") > "$DMG.sha256"
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$UPDATE_KEY_ACCOUNT" "$ZIP")
# A scratch feed is prepared; the tracked/public appcast is never advanced here.
cp appcast.xml "$OUTPUT/appcast.xml"
python3 scripts/make-appcast.py --appcast "$OUTPUT/appcast.xml" --version "$BETA_VERSION" --build "$BETA_BUILD" --url "$UPDATE_DOWNLOAD_PREFIX/$(basename "$ZIP")" --signature-output "$SIGNATURE" --notes docs/releases/RETIREMENT_0.5.1.md
printf 'Prepared signed, unpublished retirement package in %s\n' "$OUTPUT"
