#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
. ./scripts/update-config.sh
python3 scripts/archive-app.py before-build "$BETA_APP_NAME.app"
./scripts/swift.sh build -c release --arch "$BETA_ARCH" \
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=/build/BYE" \
    -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/build/BYE" \
    -Xswiftc -file-prefix-map -Xswiftc "$HOME=/build/home" \
    -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/build/home"
BIN_DIR=$(./scripts/swift.sh build -c release --arch "$BETA_ARCH" --show-bin-path)
APP="$(pwd)/dist/$BETA_APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Classwise" "$APP/Contents/MacOS/Classwise"
chmod +x "$APP/Contents/MacOS/Classwise"
# Remove debug records before signing; preserve runtime symbols.
xcrun strip -S "$APP/Contents/MacOS/Classwise"
for bundle in "$BIN_DIR"/Classwise_Classwise.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$APP/Contents/Resources/"
    fi
done
# Bundle.module expects an unconventional app-root location. Load the reader
# directly from Contents/Resources in the packaged app to keep signing valid.
rm -rf "$APP/Classwise_Classwise.bundle"
cp Sources/Classwise/Resources/RMPReader.js "$APP/Contents/Resources/RMPReader.js"
cp Sources/Classwise/Resources/THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp Sources/Classwise/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Sources/Classwise/Resources/LibreBaskerville-SemiBold.ttf "$APP/Contents/Resources/LibreBaskerville-SemiBold.ttf"
cp Sources/Classwise/Resources/LibreBaskerville-Bold.ttf "$APP/Contents/Resources/LibreBaskerville-Bold.ttf"
./scripts/embed-sparkle.sh "$BIN_DIR" "$APP"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$BETA_APP_NAME</string>
<key>CFBundleDisplayName</key><string>$BETA_APP_NAME</string>
<key>CFBundleIdentifier</key><string>local.classwise.mac.apple-ai-beta</string>
<key>CFBundleExecutable</key><string>Classwise</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$BETA_SHORT_VERSION</string>
<key>CFBundleGetInfoString</key><string>$BETA_VERSION</string>
<key>CFBundleVersion</key><string>$BETA_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>BYEWebsiteURL</key><string>$UPDATE_SITE</string>
<key>SUFeedURL</key><string>$UPDATE_FEED_URL</string>
<key>SUPublicEDKey</key><string>$UPDATE_PUBLIC_ED_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUAllowsAutomaticUpdates</key><true/>
<key>SUAutomaticallyUpdate</key><true/>
<key>SUEnableSystemProfiling</key><false/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
python3 scripts/check-distribution-privacy.py "$APP"
./scripts/sign-app.sh "$APP"
python3 scripts/archive-app.py after-build "$BETA_APP_NAME.app"
printf 'Built %s\n' "$APP"
