#!/usr/bin/env bash
# Usage: build-ids.sh <rev> [slug]   (slug defaults to "main")
#
# Prints the per-commit artifact identities as GITHUB_OUTPUT-style lines:
#
#   image-tag=<slug>-<ts>-<sha8>
#   chart-version=0.0.0-main.<ts>.g<sha8>
#
# <ts> is the committer time in UTC (YYYYMMDDHHMMSS), so both sort in commit
# order: Kargo selects the newest image Lexically and the newest chart by
# SemVer ('>=0.0.0-0 <0.0.1-0'). Content-addressed builds give chart-only
# commits the *same* image digest and build time, so the timestamp in the tag
# is what keeps image selection deterministic. The sha ties chart to image;
# the "g" prefix keeps an all-digit sha from becoming an invalid numeric
# prerelease identifier. Deterministic per commit, so release.yml recomputes
# these to find what dev ran.
set -euo pipefail

sha=$(git rev-parse --verify "${1:-HEAD}^{commit}")
slug=${2:-main}
ts=$(TZ=UTC git show -s --date=format-local:%Y%m%d%H%M%S --format=%cd "$sha")
echo "image-tag=${slug}-${ts}-${sha:0:8}"
echo "chart-version=0.0.0-main.${ts}.g${sha:0:8}"
