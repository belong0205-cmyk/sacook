#!/bin/zsh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This folder is not a Git repository." >&2
  exit 1
fi

git config core.hooksPath .githooks
git config pull.rebase true
git config rebase.autoStash true
git config fetch.prune true
git config push.autoSetupRemote true

chmod +x .githooks/pre-commit Scripts/setup-sync.sh Scripts/sync.sh

echo "Two-Mac sync is ready."
echo "Run ./Scripts/sync.sh whenever you start or finish work."

