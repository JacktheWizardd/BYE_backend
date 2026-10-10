#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
python3 scripts/archive-app.py before-build "BYE Apple AI Beta.app"
./scripts/swift.sh build -c release --arch "$BETA_ARCH" \
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=/build/BYE" \
    -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/build/BYE" \
    -Xswiftc -file-prefix-map -Xswiftc "$HOME=/build/home" \
    -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/build/home"
BIN_DIR=$(./scripts/swift.sh build -c release --arch "$BETA_ARCH" --show-bin-path)
APP="$(pwd)/dist/BYE Apple AI Beta.app"
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
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BYE Apple AI Beta</string>
<key>CFBundleDisplayName</key><string>BYE Apple AI Beta</string>
<key>CFBundleIdentifier</key><string>local.classwise.mac.apple-ai-beta</string>
<key>CFBundleExecutable</key><string>Classwise</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$BETA_SHORT_VERSION</string>
<key>CFBundleGetInfoString</key><string>$BETA_VERSION</string>
<key>CFBundleVersion</key><string>$BETA_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
python3 scripts/check-distribution-privacy.py "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
python3 scripts/archive-app.py after-build "BYE Apple AI Beta.app"
printf 'Built %s\n' "$APP"
