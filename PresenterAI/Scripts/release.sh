#!/bin/zsh
set -euo pipefail
# Package an in-app update without replacing a bundle that has an active session.
case "${1:-}" in
  ""|--package-only) ;;
  *) echo "Usage: release.sh [--package-only]" >&2; exit 2 ;;
esac
ROOT="${0:A:h:h}"
OUTPUT="$ROOT/../outputs"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
CANONICAL_VERSION="$VERSION"
[[ "$CANONICAL_VERSION" == *.*.* ]] || CANONICAL_VERSION="$CANONICAL_VERSION.0"
"$ROOT/build-app.sh"
/bin/zsh "$ROOT/Scripts/test.sh"
PACKAGE_ROOT="$(mktemp -d /private/tmp/sa-cook-release.XXXXXX)"
APP="$PACKAGE_ROOT/SA Cook Assistant.app"
/usr/bin/ditto --norsrc --noextattr --noqtn "$ROOT/dist/Presenter AI.app" "$APP"
/usr/bin/xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
ARCHIVE="$PACKAGE_ROOT/SA-Cook-Assistant-v$VERSION.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noqtn -c -k --keepParent "$APP" "$ARCHIVE"
mkdir "$PACKAGE_ROOT/verify"
/usr/bin/ditto -x -k "$ARCHIVE" "$PACKAGE_ROOT/verify"
codesign --verify --deep --strict "$PACKAGE_ROOT/verify/SA Cook Assistant.app"
ACTUAL="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PACKAGE_ROOT/verify/SA Cook Assistant.app/Contents/Info.plist")"
[[ "$ACTUAL" == "$VERSION" ]]
mkdir -p "$OUTPUT"
if [[ "${1:-}" != --package-only ]]; then
  if [[ -d "$OUTPUT/SA Cook Assistant.app" ]]; then mv "$OUTPUT/SA Cook Assistant.app" "$OUTPUT/SA Cook Assistant.app.backup-$(date +%Y%m%d%H%M%S)"; fi
  /usr/bin/ditto --norsrc --noextattr --noqtn "$APP" "$OUTPUT/SA Cook Assistant.app"
fi
if [[ -f "$OUTPUT/SA-Cook-Assistant-v$VERSION.zip" ]]; then mv "$OUTPUT/SA-Cook-Assistant-v$VERSION.zip" "$OUTPUT/SA-Cook-Assistant-v$VERSION.zip.backup-$(date +%Y%m%d%H%M%S)"; fi
cp "$ARCHIVE" "$OUTPUT/SA-Cook-Assistant-v$VERSION.zip"
PREFERRED="$OUTPUT/SA-Cook-Assistant-macOS-v$CANONICAL_VERSION.zip"
if [[ -f "$PREFERRED" ]]; then mv "$PREFERRED" "$PREFERRED.backup-$(date +%Y%m%d%H%M%S)"; fi
cp "$ARCHIVE" "$PREFERRED"
(cd "$OUTPUT" && shasum -a 256 "${PREFERRED:t}" > "${PREFERRED:t}.sha256")
cat "$PREFERRED.sha256"
echo "Verified update ready: $VERSION"
