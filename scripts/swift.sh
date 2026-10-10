#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Keep compiler caches within the project and use the SDK that matches Xcode.
# Foundation Models requires the modern macOS SDK.
mkdir -p .build/ModuleCache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
SWIFT_BIN=${CLASSWISE_SWIFT_BIN:-/usr/bin/swift}
if [ -z "${CLASSWISE_SWIFT_BIN:-}" ] && [ -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift ]; then
    SWIFT_BIN=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK_PATH=${CLASSWISE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}
set -- "$@" --sdk "$SDK_PATH"
if [ "${1:-}" = "test" ] && [ -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks ]; then
    TEST_FRAMEWORKS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
    TEST_LIBS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib
    # Expose XCTest alone for the explicit runner; Swift Testing is not used.
    mkdir -p .build/test-frameworks
    ln -sfn "$TEST_FRAMEWORKS/XCTest.framework" .build/test-frameworks/XCTest.framework
    ln -sfn "$TEST_FRAMEWORKS/XCUIAutomation.framework" .build/test-frameworks/XCUIAutomation.framework
    set -- "$@" --disable-xctest --disable-swift-testing -Xswiftc -F -Xswiftc "$PWD/.build/test-frameworks" -Xswiftc -I -Xswiftc "$TEST_LIBS" -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" -Xlinker -L -Xlinker "$TEST_LIBS" -Xlinker -rpath -Xlinker "$TEST_LIBS"
fi
if [ "${1:-}" = "test" ] && [ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xctest ]; then
    "$SWIFT_BIN" "$@" --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
    for bundle in .build/*/debug/ClasswisePackageTests.xctest; do
        if [ -d "$bundle" ]; then exec /Applications/Xcode.app/Contents/Developer/usr/bin/xctest "$bundle"; fi
    done
    printf 'No compiled XCTest bundle found.\n' >&2
    exit 1
fi
exec "$SWIFT_BIN" "$@" --build-system native --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
