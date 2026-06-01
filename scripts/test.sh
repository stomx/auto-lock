#!/bin/sh
# Run the AutoLockCore unit tests (swift-testing).
#
# This machine has Command Line Tools only (no Xcode.app), so `swift test`
# cannot find the swift-testing module or its runtime dylib on its own. We
# point the compiler and linker at the CLT-bundled Testing.framework and the
# lib_TestingInterop.dylib that lives one directory up from it. See
# docs/02-design/features/proximity-timing-fix.design.md for why the domain
# logic was split into AutoLockCore in the first place.
set -e

FW="$(xcode-select -p)/Library/Developer/Frameworks"
LIB="$(xcode-select -p)/Library/Developer/usr/lib"

if [ ! -d "$FW/Testing.framework" ]; then
    echo "Testing.framework not found at $FW" >&2
    echo "Install Xcode or a Command Line Tools version that bundles swift-testing." >&2
    exit 1
fi

exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
