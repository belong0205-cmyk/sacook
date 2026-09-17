#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
REPO="${SA_COOK_GITHUB_REPO:-belong0205-cmyk/sacook}"
TARGET="${SA_COOK_RELEASE_TARGET:-main}"
SKIP_BUILD=0
if (( $# == 1 )) && [[ "$1" == "--skip-build" ]]; then
  SKIP_BUILD=1
elif (( $# != 0 )); then
  echo "Usage: publish-all.sh [--skip-build]" >&2
  exit 2
fi

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 1; }
gh auth status >/dev/null

(( SKIP_BUILD )) || /bin/zsh "$ROOT/Scripts/build-all.sh"
/bin/zsh "$ROOT/Scripts/verify-sync.sh" --built

VERSION="$(node -p "require('$ROOT/Shared/feature-manifest.json').featureVersion")"
MAJOR="${VERSION%%.*}"
REST="${VERSION#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"
[[ "$PATCH" == "0" ]] || {
  echo "Legacy Windows preview updates require a major.minor.0 feature version." >&2
  exit 1
}

SHORT_VERSION="$MAJOR.$MINOR"
MAC_TAG="v$VERSION"
WIN_TAG="v$SHORT_VERSION-windows-preview.1"
MAC_ZIP="$ROOT/outputs/SA-Cook-Assistant-macOS-v$VERSION.zip"
WIN_ZIP="$ROOT/outputs/SA-Cook-Assistant-Windows-x64-v$VERSION-preview.zip"
MAC_NOTES="$ROOT/PresenterAI/PATCH-v$SHORT_VERSION.md"
WIN_NOTES="$ROOT/PresenterAI-Windows/PATCH-WINDOWS-v$SHORT_VERSION-preview.md"

for file in "$MAC_ZIP" "$MAC_ZIP.sha256" "$WIN_ZIP" "$WIN_ZIP.sha256" "$MAC_NOTES" "$WIN_NOTES"; do
  test -s "$file" || { echo "Missing release file: $file" >&2; exit 1; }
done

(cd "$ROOT/outputs" && \
  shasum -a 256 -c "${MAC_ZIP:t}.sha256" && \
  shasum -a 256 -c "${WIN_ZIP:t}.sha256")

release_id_for_tag() {
  local tag="$1"
  gh api "repos/$REPO/releases?per_page=100" --jq ".[] | select(.tag_name == \"$tag\") | .id"
}

assert_release_absent() {
  local tag="$1" release_id
  release_id="$(release_id_for_tag "$tag")"
  [[ -z "$release_id" ]] || { echo "Release already exists: $tag" >&2; exit 1; }
}

assert_tag_absent() {
  local tag="$1" response
  if response="$(gh api "repos/$REPO/git/ref/tags/$tag" 2>&1)"; then
    echo "Git tag already exists without the expected release: $tag" >&2
    exit 1
  fi
  if [[ "$response" != *"HTTP 404"* ]]; then
    echo "$response" >&2
    echo "Could not confirm that tag $tag is absent." >&2
    exit 1
  fi
}

verify_asset() {
  local release_id="$1" file="$2" name="${2:t}" details remote_size remote_digest local_size local_digest
  details="$(gh api "repos/$REPO/releases/$release_id" --jq ".assets[] | select(.name == \"$name\") | [(.size|tostring), .digest] | @tsv")"
  [[ -n "$details" ]] || { echo "Missing remote asset: $name" >&2; return 1; }
  remote_size="${details%%$'\t'*}"
  remote_digest="${details#*$'\t'}"
  local_size="$(stat -f '%z' "$file")"
  local_digest="sha256:$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$remote_size" == "$local_size" ]] || { echo "Remote size mismatch: $name" >&2; return 1; }
  [[ "$remote_digest" == "$local_digest" ]] || { echo "Remote SHA-256 mismatch: $name" >&2; return 1; }
}

verify_release() {
  local release_id="$1" tag="$2" expected_draft="$3" expected_prerelease="$4" zip="$5" state assets expected
  state="$(gh api "repos/$REPO/releases/$release_id" --jq '[.draft,.prerelease] | map(tostring) | join(" ")')"
  [[ "$state" == "$expected_draft $expected_prerelease" ]] || { echo "Unexpected release state for $tag: $state" >&2; return 1; }
  assets="$(gh api "repos/$REPO/releases/$release_id" --jq '[.assets[].name] | sort | join("\n")')"
  expected="$(printf '%s\n%s' "${zip:t}" "${zip:t}.sha256" | sort)"
  [[ "$assets" == "$expected" ]] || { echo "Unexpected release assets for $tag." >&2; return 1; }
  verify_asset "$release_id" "$zip"
  verify_asset "$release_id" "$zip.sha256"
}

assert_release_absent "$MAC_TAG"
assert_release_absent "$WIN_TAG"
assert_tag_absent "$MAC_TAG"
assert_tag_absent "$WIN_TAG"
TARGET_SHA="$(gh api "repos/$REPO/commits/$TARGET" --jq .sha)"
[[ ${#TARGET_SHA} -ge 40 && "$TARGET_SHA" != *[^0-9a-f]* ]] || { echo "Invalid release target: $TARGET" >&2; exit 1; }

CREATED_MAC=0
CREATED_WIN=0
MAC_RELEASE_ID=""
WIN_RELEASE_ID=""
delete_created_release() {
  local tag="$1" release_id="$2"
  if [[ -z "$release_id" ]]; then release_id="$(release_id_for_tag "$tag" 2>/dev/null || true)"; fi
  if [[ -n "$release_id" && "$release_id" != *[^0-9]* ]]; then
    gh api --method DELETE "repos/$REPO/releases/$release_id" >/dev/null 2>&1 || true
  fi
  if gh api "repos/$REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
    gh api --method DELETE "repos/$REPO/git/refs/tags/$tag" >/dev/null 2>&1 || true
  fi
}
rollback_created_releases() {
  local exit_code=$?
  trap - EXIT
  if (( exit_code != 0 )); then
    echo "Publish failed; removing only the releases created by this run." >&2
    (( CREATED_MAC )) && delete_created_release "$MAC_TAG" "$MAC_RELEASE_ID" || true
    (( CREATED_WIN )) && delete_created_release "$WIN_TAG" "$WIN_RELEASE_ID" || true
  fi
  exit "$exit_code"
}
trap rollback_created_releases EXIT

# Keep stable releases macOS-only while legacy macOS clients still select the
# first ZIP asset. Create and verify both releases as drafts before either one
# becomes visible. Windows remains on its compatible preview update channel.
CREATED_MAC=1
gh release create "$MAC_TAG" \
  "$MAC_ZIP" "$MAC_ZIP.sha256" \
  --repo "$REPO" \
  --target "$TARGET" \
  --title "SA Cook Assistant $SHORT_VERSION" \
  --notes-file "$MAC_NOTES" \
  --draft
MAC_RELEASE_ID="$(release_id_for_tag "$MAC_TAG")"
[[ -n "$MAC_RELEASE_ID" && "$MAC_RELEASE_ID" != *[^0-9]* ]] || { echo "Could not resolve macOS draft release ID." >&2; exit 1; }

CREATED_WIN=1
gh release create "$WIN_TAG" \
  "$WIN_ZIP" "$WIN_ZIP.sha256" \
  --repo "$REPO" \
  --target "$TARGET" \
  --title "SA Cook Assistant Windows Preview $SHORT_VERSION" \
  --notes-file "$WIN_NOTES" \
  --prerelease \
  --draft
WIN_RELEASE_ID="$(release_id_for_tag "$WIN_TAG")"
[[ -n "$WIN_RELEASE_ID" && "$WIN_RELEASE_ID" != *[^0-9]* ]] || { echo "Could not resolve Windows draft release ID." >&2; exit 1; }

verify_release "$MAC_RELEASE_ID" "$MAC_TAG" true false "$MAC_ZIP"
verify_release "$WIN_RELEASE_ID" "$WIN_TAG" true true "$WIN_ZIP"

# Publish Windows first. If publishing macOS fails, the EXIT trap removes the
# new Windows release so the two update channels cannot remain out of sync.
gh api --method PATCH "repos/$REPO/releases/$WIN_RELEASE_ID" -F draft=false -F prerelease=true -f make_latest=false >/dev/null
gh api --method PATCH "repos/$REPO/releases/$MAC_RELEASE_ID" -F draft=false -F prerelease=false -f make_latest=true >/dev/null

verify_release "$MAC_RELEASE_ID" "$MAC_TAG" false false "$MAC_ZIP"
verify_release "$WIN_RELEASE_ID" "$WIN_TAG" false true "$WIN_ZIP"
[[ "$(gh api "repos/$REPO/releases/latest" --jq .tag_name)" == "$MAC_TAG" ]] || { echo "macOS release is not GitHub Latest." >&2; exit 1; }
[[ "$(gh api "repos/$REPO/git/ref/tags/$MAC_TAG" --jq .object.sha)" == "$TARGET_SHA" ]] || { echo "macOS tag target mismatch." >&2; exit 1; }
[[ "$(gh api "repos/$REPO/git/ref/tags/$WIN_TAG" --jq .object.sha)" == "$TARGET_SHA" ]] || { echo "Windows tag target mismatch." >&2; exit 1; }

trap - EXIT
echo "Published synchronized updates: $MAC_TAG and $WIN_TAG"
