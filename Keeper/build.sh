#!/bin/bash
# Builds Keeper.app with the Command Line Tools (no Xcode needed).
# Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Keeper.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(Sources/*.swift)

# Find an SDK that this Swift compiler can use. After some Command Line Tools
# updates, the newest SDK is built with a newer Swift than the compiler.
SDK=""
TEST="$(mktemp -d)/sdktest.swift"
echo 'import SwiftUI' > "$TEST"
CANDIDATES=()
[ -n "${SDKROOT:-}" ] && CANDIDATES+=("$SDKROOT")
CANDIDATES+=("$(xcrun --show-sdk-path 2>/dev/null || true)")
while IFS= read -r dir; do CANDIDATES+=("$dir"); done < <(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r)
for candidate in "${CANDIDATES[@]}"; do
    [ -d "$candidate" ] || continue
    if swiftc -typecheck -sdk "$candidate" -target arm64-apple-macos13.0 "$TEST" >/dev/null 2>&1; then
        SDK="$candidate"
        break
    fi
done
if [ -z "$SDK" ]; then
    echo "No SDK works with this Swift compiler ($(swiftc --version 2>&1 | head -n 1))."
    echo "Available SDKs:"
    ls /Library/Developer/CommandLineTools/SDKs
    exit 1
fi
echo "Using SDK: $SDK"

for ARCH in arm64 x86_64; do
    echo "Compiling for ${ARCH}..."
    swiftc -O -parse-as-library \
        -sdk "$SDK" \
        -target "$ARCH-apple-macos13.0" \
        -o "build/Keeper-$ARCH" \
        "${SOURCES[@]}"
done

lipo -create -output "$APP/Contents/MacOS/Keeper" build/Keeper-arm64 build/Keeper-x86_64
rm build/Keeper-arm64 build/Keeper-x86_64

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo ""
echo "Done: $(pwd)/$APP"
echo "Drag it to /Applications in Finder. Finder asks for an administrator password."
