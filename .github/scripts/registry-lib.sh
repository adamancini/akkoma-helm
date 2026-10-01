#!/usr/bin/env bash
# Registry lookups that tell "not found" apart from every other failure.
# Treating an auth error, 5xx or rate limit as "absent" would let a workflow
# overwrite a published chart or move a release image tag, since ghcr tags
# are mutable. Source this file; each function returns 0 = present,
# 1 = absent, and fails the step (exit 2 from the caller's shell) on errors.
#
# Call as `x=$(fn ...) && rc=0 || rc=$?` -- an `exit` inside $(...) only
# leaves the subshell, so the caller must check for rc 2 itself.

# Prints the manifest (index) digest of an image ref.
image_digest() {
  local out
  if out=$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>&1); then
    jq -r .digest <<<"$out"
    return 0
  fi
  if grep -q ': not found' <<<"$out"; then
    return 1
  fi
  echo "::error::looking up image $1 failed: $out" >&2
  return 2
}

# chart_present <oci-repo>/<name> <version>
chart_present() {
  local out
  if out=$(helm show chart "$1" --version "$2" 2>&1); then
    return 0
  fi
  if grep -q ': not found' <<<"$out"; then
    return 1
  fi
  echo "::error::looking up chart $1:$2 failed: $out" >&2
  return 2
}
