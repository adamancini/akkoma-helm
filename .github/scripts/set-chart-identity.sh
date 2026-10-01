#!/usr/bin/env bash
# Usage: set-chart-identity.sh <chart-dir> <version> <image-tag>
#
# Sets Chart.yaml `version` and values.yaml `image.tag` in place, touching
# nothing else (line edits, not a YAML round-trip, so comments and formatting
# survive). An empty image tag means "default to appVersion". These are the
# only two fields allowed to differ between a dev-lane chart and the release
# chart repackaged from it; release.yml verifies that by reversing the edit.
set -euo pipefail

dir=$1 version=$2 tag=$3

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: '$version' is not a SemVer chart version" >&2
  exit 1
fi
if [[ -n "$tag" && ! "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "ERROR: '$tag' is not a valid image tag" >&2
  exit 1
fi

if [[ $(grep -c '^version:' "$dir/Chart.yaml") -ne 1 ]]; then
  echo "ERROR: expected exactly one top-level 'version:' in $dir/Chart.yaml" >&2
  exit 1
fi
sed -E "s/^version:.*/version: ${version}/" "$dir/Chart.yaml" > "$dir/Chart.yaml.tmp"
mv "$dir/Chart.yaml.tmp" "$dir/Chart.yaml"

# Replace the quoted value of the first `  tag:` inside the top-level `image:`
# block, keeping any trailing comment.
if ! awk -v tag="$tag" '
  /^[^[:space:]#]/ { inimage = ($0 ~ /^image:/) }
  inimage && !done && /^  tag:/ {
    if (sub(/tag:[[:space:]]*"[^"]*"/, "tag: \"" tag "\"")) done = 1
  }
  { print }
  END { exit done ? 0 : 1 }
' "$dir/values.yaml" > "$dir/values.yaml.tmp"; then
  rm -f "$dir/values.yaml.tmp"
  echo "ERROR: no quoted image.tag found in $dir/values.yaml" >&2
  exit 1
fi
mv "$dir/values.yaml.tmp" "$dir/values.yaml"
