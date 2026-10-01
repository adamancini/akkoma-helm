#!/usr/bin/env bash
# Prints the dev-lane chart version for a commit:
#
#   0.0.0-main.<committer time, UTC, YYYYMMDDHHMMSS>.g<sha8>
#
# The timestamp makes versions sort in commit order (Kargo picks the highest
# SemVer matching '>=0.0.0-0 <0.0.1-0'); the sha ties the chart to the
# main-<sha8> image it pins. The "g" prefix keeps an all-digit sha from
# becoming an invalid numeric prerelease identifier. Deterministic per commit,
# so release.yml can recompute it to find the chart dev ran.
set -euo pipefail

sha=$(git rev-parse --verify "${1:-HEAD}^{commit}")
ts=$(TZ=UTC git show -s --date=format-local:%Y%m%d%H%M%S --format=%cd "$sha")
echo "0.0.0-main.${ts}.g${sha:0:8}"
