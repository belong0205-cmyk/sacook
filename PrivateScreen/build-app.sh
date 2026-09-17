#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/dist/Private Screen.app"

cd "$ROOT"
mkdir -p "$ROOT/build"
clang -fobjc-arc -framework Cocoa -mmacosx-version-min=13.0 \
    "$ROOT/Sources/main.m" -o "$ROOT/build/PrivateScreen"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/build/PrivateScreen" "$APP/Contents/MacOS/PrivateScreen"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "$APP"
