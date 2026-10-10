#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
BIN_DIR=$(./scripts/swift.sh build -c release --show-bin-path)
APP="$(pwd)/dist/BYE.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Classwise" "$APP/Contents/MacOS/Classwise"
for bundle in "$BIN_DIR"/Classwise_Classwise.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$APP/Contents/Resources/"
    fi
done
# Bundle.module expects an unconventional app-root location. Load the reader
# directly from Contents/Resources in the packaged app to keep signing valid.
rm -rf "$APP/Classwise_Classwise.bundle"
cp Sources/Classwise/Resources/RMPReader.js "$APP/Contents/Resources/RMPReader.js"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BYE</string>
<key>CFBundleDisplayName</key><string>BYE — Before You Enroll</string>
<key>CFBundleIdentifier</key><string>local.classwise.mac</string>
<key>CFBundleExecutable</key><string>Classwise</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"
