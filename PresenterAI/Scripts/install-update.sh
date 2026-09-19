#!/bin/sh
# The app prepares and verifies a complete staging bundle BEFORE it quits.
set -u
target=$1
staged=$2
old_pid=$3
work=$4
log=$5
original=${6:-$target}
exec >> "$log" 2>&1
cd /private/tmp || exit 1
echo "Installing update at $(date)"
backup="$work/previous.app"
health="$work/ready"
attempt=0
while kill -0 "$old_pid" 2>/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 90 ] || { echo 'Old process did not exit; installation was not changed.'; exit 1; }
  sleep 1
done
had_old=0
if [ -e "$target" ]; then
  mv "$target" "$backup" || { echo 'Cannot move old application'; /usr/bin/open "$target"; exit 1; }
  had_old=1
fi
new_pid=''
restore() {
  echo 'New application failed; restoring previous application.'
  if [ -n "$new_pid" ]; then kill "$new_pid" 2>/dev/null || true; wait "$new_pid" 2>/dev/null || true; fi
  # Keep the failed bundle for diagnosis; never delete a user's unrelated path.
  if [ -e "$target" ]; then mv "$target" "$work/failed.app" || exit 1; fi
  if [ "$had_old" = 1 ]; then mv "$backup" "$target" && /usr/bin/open "$target";
  else /usr/bin/open "$original"; fi
  exit 1
}
mv "$staged" "$target" || restore
"$target/Contents/MacOS/PresenterAI" "--sa-cook-update-health=$health" &
new_pid=$!
attempt=0
while [ "$attempt" -lt 40 ]; do
  if [ -f "$health" ]; then
    echo 'Updated application is ready. Previous bundle retained in staging backup.'
    exit 0
  fi
  kill -0 "$new_pid" 2>/dev/null || restore
  sleep 1
  attempt=$((attempt + 1))
done
restore
