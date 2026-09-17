#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MODE="${1:-source}"
[[ "$MODE" == "source" || "$MODE" == "--built" ]] || { echo "Usage: verify-sync.sh [--built]" >&2; exit 2; }
MAC_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/PresenterAI/Info.plist")"
WIN_VERSION="$(node -p "require('$ROOT/PresenterAI-Windows/package.json').version")"
FEATURE_VERSION="$(node -p "require('$ROOT/Shared/feature-manifest.json').featureVersion")"

normalise_version() {
  local value="$1"
  local major="${value%%.*}"
  local rest="${value#*.}"
  local minor="${rest%%.*}"
  local patch="0"
  [[ "$rest" == *.* ]] && patch="${rest#*.}"
  echo "$major.$minor.$patch"
}

[[ "$(normalise_version "$MAC_VERSION")" == "$WIN_VERSION" ]]
[[ "$WIN_VERSION" == "$FEATURE_VERSION" ]]
test -s "$ROOT/Shared/answer-policy.txt"
rg -q 'CEFR B2' "$ROOT/Shared/answer-policy.txt"
rg -q 'answer-policy.txt' "$ROOT/PresenterAI/build-app.sh"
rg -q 'answer-policy.txt' "$ROOT/PresenterAI-Windows/build-preview.sh"
rg -q 'SCAudioUtteranceBuffer.m' "$ROOT/PresenterAI/build-app.sh"
rg -q 'gpt-transcribe' "$ROOT/PresenterAI/Sources/main.m"
rg -q 'gpt-transcribe' "$ROOT/PresenterAI-Windows/app.js"
! rg -q 'gpt-live-transcribe' "$ROOT/PresenterAI-Windows/app.js"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$ROOT/PresenterAI/Info.plist")" == "true" ]]
rg -q 'NSApplicationActivationPolicyAccessory' "$ROOT/PresenterAI/Sources/main.m"
rg -q 'skipTaskbar: true' "$ROOT/PresenterAI-Windows/main.js"
node "$ROOT/PresenterAI-Windows/tests/update-source.test.js"

MAC_RESOURCES="$ROOT/PresenterAI/dist/Presenter AI.app/Contents/Resources"
WIN_RESOURCES="$ROOT/PresenterAI-Windows/resources"
if [[ "$MODE" == "--built" ]]; then
  test -d "$MAC_RESOURCES"
  cmp "$ROOT/Shared/answer-policy.txt" "$MAC_RESOURCES/answer-policy.txt"
  cmp "$ROOT/Shared/feature-manifest.json" "$MAC_RESOURCES/feature-manifest.json"
  cmp "$ROOT/Shared/ui-tokens.json" "$MAC_RESOURCES/ui-tokens.json"
  for name in sa-cook-qa.json internet-qa.json speech-hints.txt sa-cook-knowledge.txt sa-cook-handbook.txt; do
    test -f "$MAC_RESOURCES/$name"
    test -f "$WIN_RESOURCES/$name"
    cmp "$MAC_RESOURCES/$name" "$WIN_RESOURCES/$name"
  done
fi

echo "macOS and Windows feature contract verified at $FEATURE_VERSION"
