#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
if [ "$BETA_VERSION" = 0.5.1 ]; then exec ./scripts/build-retirement-app.sh --test; fi
. ./scripts/schedule-api-config.sh
. ./scripts/update-config.sh
# Updates stay off in test builds. BYE_TEST_UPDATES=1 writes the release feed and key so Settings → Updates and
# "Check for Updates…" can be tried; set BYE_UPDATE_FEED_URL to a localhost appcast to test without the live feed.
UPDATE_PLIST=""
if [ "${BYE_TEST_UPDATES:-0}" = 1 ]; then
    UPDATE_PLIST="<key>SUFeedURL</key><string>$UPDATE_FEED_URL</string><key>SUPublicEDKey</key><string>$UPDATE_PUBLIC_ED_KEY</string>"
fi

./scripts/swift.sh build -c release --arch "$BETA_ARCH"
BIN_DIR=$(./scripts/swift.sh build -c release --arch "$BETA_ARCH" --show-bin-path)
mkdir -p test
STAGING=$(mktemp -d "$PWD/test/.build-XXXXXX")
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
APP="$PWD/test/BYE Test.app"
STAGED_APP="$STAGING/BYE Test.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/Classwise" "$STAGED_APP/Contents/MacOS/Classwise"
chmod +x "$STAGED_APP/Contents/MacOS/Classwise"
if [ -d "$BIN_DIR/Classwise_Classwise.bundle" ]; then
    cp -R "$BIN_DIR/Classwise_Classwise.bundle" "$STAGED_APP/Contents/Resources/"
fi
# The packaged reader loads directly from the app's resources.
cp Sources/Classwise/Resources/RMPReader.js "$STAGED_APP/Contents/Resources/"
cp Sources/Classwise/Resources/THIRD_PARTY_NOTICES.txt "$STAGED_APP/Contents/Resources/"
cp Sources/Classwise/Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/"
cp Sources/Classwise/Resources/LibreBaskerville-SemiBold.ttf "$STAGED_APP/Contents/Resources/LibreBaskerville-SemiBold.ttf"
cp Sources/Classwise/Resources/LibreBaskerville-Bold.ttf "$STAGED_APP/Contents/Resources/LibreBaskerville-Bold.ttf"
# The executable links Sparkle. Without BYE_TEST_UPDATES=1 no SUFeedURL is written, so updates stay off.
./scripts/embed-sparkle.sh "$BIN_DIR" "$STAGED_APP"
cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BYE Test</string>
<key>CFBundleDisplayName</key><string>BYE Test</string>
<key>CFBundleIdentifier</key><string>local.classwise.mac.test</string>
<key>CFBundleExecutable</key><string>Classwise</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$BETA_SHORT_VERSION</string>
<key>CFBundleVersion</key><string>$BETA_BUILD</string>
<key>CFBundleGetInfoString</key><string>Local development test build</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
$(schedule_api_plist)
$UPDATE_PLIST
</dict></plist>
PLIST
codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
rm -rf "$APP"
mv "$STAGED_APP" "$APP"
printf 'Test app ready: %s\n' "$APP"
if [ -n "$UPDATE_PLIST" ]; then printf 'Updates: on, feed %s\n' "$UPDATE_FEED_URL"; fi
if [ -n "$SCHEDULE_API_KEY" ]; then echo 'Schedule API: key included.'; else echo 'Schedule API: no key (add one to config/schedule-api.local); the app will say it is not configured.'; fi
