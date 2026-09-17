#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/Scripts/verify-sync.sh"
/bin/zsh "$ROOT/PresenterAI/Scripts/release.sh" --package-only
MAC_RESOURCES="$ROOT/PresenterAI/dist/Presenter AI.app/Contents/Resources"
WIN_RESOURCES="$ROOT/PresenterAI-Windows/resources"
for name in sa-cook-qa.json internet-qa.json speech-hints.txt sa-cook-knowledge.txt sa-cook-handbook.txt; do
  test -s "$MAC_RESOURCES/$name"
  cp "$MAC_RESOURCES/$name" "$WIN_RESOURCES/$name"
done
/bin/zsh "$ROOT/PresenterAI-Windows/build-preview.sh"
"$ROOT/Scripts/verify-sync.sh" --built
echo "Synchronized macOS and Windows packages are ready in $ROOT/outputs"
