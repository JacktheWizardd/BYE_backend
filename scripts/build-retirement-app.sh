#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/beta-version.sh
. ./scripts/update-config.sh
MODE=${1:-distribution}
./scripts/swift.sh build --product BYERetirement -c release --arch "$BETA_ARCH" \
  -Xswiftc -file-prefix-map -Xswiftc "$PWD=/build/BYE" \
  -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/build/BYE" \
  -Xswiftc -file-prefix-map -Xswiftc "$HOME=/build/home" \
  -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/build/home"
BIN_DIR=$(./scripts/swift.sh build -c release --arch "$BETA_ARCH" --show-bin-path)
NAME="$BETA_APP_NAME"
IDENTIFIER=local.classwise.mac.apple-ai-beta
PARENT="$PWD/dist/retirement"
FEED="$UPDATE_FEED_URL"
if [ "$MODE" = --test ]; then
  NAME="BYE Test"; IDENTIFIER=local.classwise.mac.test; PARENT="$PWD/test"
  if [ "${BYE_TEST_UPDATES:-0}" != 1 ]; then FEED=""; fi
elif [ "$MODE" != distribution ]; then
  echo 'Usage: build-retirement-app.sh [--test]' >&2; exit 1
fi
mkdir -p "$PARENT"
STAGE=$(mktemp -d "$PARENT/.build-retirement-XXXXXX")
APP="$STAGE/$NAME.app"
# No deletion of an existing application or its contents. Keep prior test/release builds as backups.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BYERetirement" "$APP/Contents/MacOS/Classwise"
xcrun strip -S "$APP/Contents/MacOS/Classwise"
for name in AppIcon.icns LibreBaskerville-Bold.ttf THIRD_PARTY_NOTICES.txt; do
  cp "Sources/Classwise/Resources/$name" "$APP/Contents/Resources/"
done
./scripts/embed-sparkle.sh "$BIN_DIR" "$APP"
export BYE_RETIRE_APP="$APP" BYE_RETIRE_NAME="$NAME" BYE_RETIRE_ID="$IDENTIFIER" BYE_RETIRE_FEED="$FEED"
export BYE_RETIRE_VERSION="$BETA_SHORT_VERSION" BYE_RETIRE_BUILD="$BETA_BUILD" BYE_RETIRE_PUBLIC_KEY="$UPDATE_PUBLIC_ED_KEY"
python3 - <<'PLIST'
import os, pathlib, plistlib
v=lambda key:os.environ['BYE_RETIRE_'+key]
p={"CFBundleName":v('NAME'),"CFBundleDisplayName":v('NAME'),"CFBundleIdentifier":v('ID'),"CFBundleExecutable":"Classwise","CFBundleIconFile":"AppIcon.icns","CFBundlePackageType":"APPL","CFBundleShortVersionString":v('VERSION'),"CFBundleGetInfoString":v('VERSION'),"CFBundleVersion":v('BUILD'),"LSMinimumSystemVersion":"14.0","NSHighResolutionCapable":True,"SUEnableAutomaticChecks":True,"SUScheduledCheckInterval":86400,"SUAllowsAutomaticUpdates":True,"SUAutomaticallyUpdate":True,"SUEnableSystemProfiling":False}
if v('FEED'):p.update(SUFeedURL=v('FEED'),SUPublicEDKey=v('PUBLIC_KEY'))
with (pathlib.Path(v('APP'))/'Contents/Info.plist').open('wb') as f:plistlib.dump(p,f)
PLIST
python3 scripts/check-distribution-privacy.py "$APP"
./scripts/sign-app.sh "$APP"
python3 scripts/retirement/verify-mac.py "$APP"
if [ -e "$PARENT/$NAME.app" ]; then
  BACKUP=$(mktemp -d "$PARENT/.previous-retirement-XXXXXX")
  mv "$PARENT/$NAME.app" "$BACKUP/"
fi
mv "$APP" "$PARENT/$NAME.app"
rmdir "$STAGE"
printf 'Retirement app ready: %s\n' "$PARENT/$NAME.app"
