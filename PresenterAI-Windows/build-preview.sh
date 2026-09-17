#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT="$ROOT/../outputs"
VERSION="$(node -p "require('$ROOT/package.json').version")"
export HOME="$ROOT/.home"
export ELECTRON_CACHE="$ROOT/.home/Library/Caches/electron"

APP="$ROOT/dist/SA Cook Assistant-win32-x64"
RUNTIME_ZIP="$(find "$ELECTRON_CACHE" -name 'electron-v37.10.3-win32-x64.zip' -type f -print -quit)"
[[ -n "$RUNTIME_ZIP" ]] || { echo 'Khong tim thay Electron Windows runtime.' >&2; exit 1; }
/usr/bin/unzip -tq "$RUNTIME_ZIP"

rm -rf "$APP"
mkdir -p "$APP"
/usr/bin/ditto -x -k "$RUNTIME_ZIP" "$APP"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sa-cook-win.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
node "$ROOT/tests/b1-policy.test.js"
node --check "$ROOT/main.js"
node --check "$ROOT/preload.js"
node --check "$ROOT/b1-policy.js"
node --check "$ROOT/app.js"
cp "$ROOT/package.json" "$ROOT/main.js" "$ROOT/preload.js" "$ROOT/index.html" "$ROOT/style.css" "$ROOT/b1-policy.js" "$ROOT/turn-policy.js" "$ROOT/app.js" "$STAGE/"
cp -R "$ROOT/resources" "$STAGE/resources"
for SHARED_RESOURCE in answer-policy.txt feature-manifest.json ui-tokens.json; do
  [[ -f "$ROOT/../Shared/$SHARED_RESOURCE" ]] || { echo "Thieu Shared/$SHARED_RESOURCE" >&2; exit 1; }
  cp "$ROOT/../Shared/$SHARED_RESOURCE" "$STAGE/resources/$SHARED_RESOURCE"
done
node "$ROOT/node_modules/.pnpm/@electron+asar@3.4.1/node_modules/@electron/asar/bin/asar.js" pack "$STAGE" "$APP/resources/app.asar"
mv "$APP/electron.exe" "$APP/SA Cook Assistant.exe"
cp "$ROOT/.sa-cook-portable-root" "$APP/.sa-cook-portable-root"

test -s "$APP/SA Cook Assistant.exe"
file "$APP/SA Cook Assistant.exe" | grep -q 'PE32+ executable.*x86-64'
[[ -f "$ROOT/HUONG-DAN-WINDOWS.txt" ]] && cp "$ROOT/HUONG-DAN-WINDOWS.txt" "$APP/HUONG-DAN.txt"

mkdir -p "$OUTPUT"
ARCHIVE="$OUTPUT/SA-Cook-Assistant-Windows-x64-v${VERSION}-preview.zip"
if [[ -f "$ARCHIVE" ]]; then mv "$ARCHIVE" "$ARCHIVE.backup-$(date +%Y%m%d%H%M%S)"; fi
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noqtn -c -k --keepParent "$APP" "$ARCHIVE"
/usr/bin/unzip -tq "$ARCHIVE"
(cd "$OUTPUT" && shasum -a 256 "${ARCHIVE:t}" > "${ARCHIVE:t}.sha256")
cat "$ARCHIVE.sha256"
STABLE_ARCHIVE="$OUTPUT/SA-Cook-Assistant-Windows-x64-v${VERSION}.zip"
if [[ -f "$STABLE_ARCHIVE" ]]; then mv "$STABLE_ARCHIVE" "$STABLE_ARCHIVE.backup-$(date +%Y%m%d%H%M%S)"; fi
cp "$ARCHIVE" "$STABLE_ARCHIVE"
(cd "$OUTPUT" && shasum -a 256 "${STABLE_ARCHIVE:t}" > "${STABLE_ARCHIVE:t}.sha256")
echo "$ARCHIVE"
