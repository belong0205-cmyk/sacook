#!/bin/zsh
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Sync stopped: Git is in detached HEAD mode." >&2
  exit 1
fi

lock_dir="$(git rev-parse --git-dir)/sa-cook-sync.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "Another sync is already running. If it is not, remove: $lock_dir" >&2
  exit 1
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM

git fetch origin --prune

if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  machine="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
  stamp="$(date '+%Y-%m-%d %H:%M:%S %z')"
  message="Sync from ${machine} at ${stamp}"
  if [[ $# -gt 0 ]]; then
    message="$*"
  fi
  git commit -m "$message"
fi

# Rebase keeps one clean shared history. Conflicts stop here without deleting work.
git pull --rebase origin "$branch"
git push origin "$branch"

echo "Sync complete: $(git rev-parse --short HEAD) on $branch"

