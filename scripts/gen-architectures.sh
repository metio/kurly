# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Generates catalog/architectures.gen.libsonnet: the linux CPU architectures each
# stage's pinned image publishes, read from the image's manifest list. A
# self-service portal reads it to keep an amd64-only image off an arm64 node
# (a per-tenant runtime failure) and to place arm-capable workloads on the
# cheaper burst tier. Derived from the registry, so it cannot be guessed wrong —
# rerun it when an image is bumped (Renovate touches the .image file, this reads
# it). check-catalog fails if an image-bearing stage has no entry.
set -uo pipefail
# Run from the repository root, like every other generator here: under nix the
# script lives in the store, so deriving the root from the script's own path
# lands in the store instead and every relative path fails.

out=catalog/architectures.gen.libsonnet

# STAGES (space-separated `<workload>/<stage>` keys) narrows the sweep to those
# stages, keeping what the last run derived for the rest — the way to re-ask the
# handful a rate limit refused without paying for the three hundred it answered.
ONLY="${STAGES:-}"
export ONLY

# What the last run derived, so an unreachable registry keeps its answer instead
# of retracting it.
PREVIOUS="$(mktemp)"
export PREVIOUS
trap 'rm -f "$PREVIOUS"' EXIT
if [ -f "$out" ]; then jsonnet "$out" 2>/dev/null > "$PREVIOUS" || echo '{}' > "$PREVIOUS"; else echo '{}' > "$PREVIOUS"; fi

# One stage: workloads/<w>/<stage>.image -> "<w>/<stage>": ["amd64",...]. A
# manifest LIST advertises its platforms; a single-arch image carries its
# architecture in the image config. An unreadable ref falls back to amd64 (the
# safe assumption — never schedules onto arm on a guess).
inspect_one() {
  local img="$1" key ref raw arches digest
  key="$(printf '%s' "$img" | sed -E 's#workloads/([^/]+)/([^/]+)\.image#\1/\2#')"
  ref="$(cat "$img")"
  # Outside a requested subset: keep what the last run derived, unasked. Three
  # hundred registries rate-limit, and re-asking the ones already answered is
  # what exhausts the budget before reaching the ones that were not.
  if [ -n "${ONLY:-}" ] && ! grep -qw -- "$key" <<<"$ONLY"; then
    local previous
    previous="$(jq --compact-output --arg key "$key" \
      '.[$key] // empty | if type == "array" then { architectures: . } else . end' "$PREVIOUS" 2>/dev/null || true)"
    [ -z "$previous" ] || printf '  "%s": %s,\n' "$key" \
      "$(printf '%s' "$previous" | sed "s/\"digest\":/digest:/; s/\"architectures\":/architectures:/; s/\"/'/g")"
    return 0
  fi
  raw="$(skopeo inspect --retry-times 3 --raw "docker://${ref}" 2>/dev/null || true)"
  if [ -z "$raw" ]; then
    # The registry did not answer. Three hundred inspects meet a rate limit
    # sooner or later, and defaulting to amd64 there would quietly retract every
    # arm64 answer a previous run earned — publishing "cannot run on arm" for an
    # image that can. So the previous answer stands, and the run reports that it
    # could not ask rather than pretending it did.
    local kept
    # Normalised on the way through: an entry written before this file carried
    # digests is a bare array, and keeping it verbatim would leave the file in
    # two shapes at once. The digest is simply absent, which is what it is.
    kept="$(jq --compact-output --arg key "$key" \
      '.[$key] // empty | if type == "array" then { architectures: . } else . end' "$PREVIOUS" 2>/dev/null || true)"
    if [ -n "$kept" ]; then
      printf '  "%s": %s,\n' "$key" "$(printf '%s' "$kept" | sed "s/\"digest\":/digest:/; s/\"architectures\":/architectures:/; s/\"/'/g")"
    else
      printf '::error::%s: registry unreachable and nothing derived before\n' "$key" >&2
    fi
    return 0
  elif printf '%s' "$raw" | jq -e '.manifests' >/dev/null 2>&1; then
    arches="$(printf '%s' "$raw" | jq -c '[.manifests[].platform | select(.os=="linux") | .architecture] | unique')"
  else
    arches="$(skopeo inspect --retry-times 3 "docker://${ref}" 2>/dev/null | jq -c '[.Architecture]' 2>/dev/null || printf '["amd64"]')"
  fi
  # A manifest's digest IS the sha256 of its own bytes, so what the tag resolves
  # to today costs nothing beyond the fetch already made. It answers the question
  # a tag cannot: whether the bits changed while the version did not — a rebuilt
  # base image carrying a patched library, which is the update most worth
  # applying quickly and least in need of a change window.
  digest=""
  [ -z "$raw" ] || digest="sha256:$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)"
  # The reference the digest was observed FOR travels with it. A Renovate bump
  # rewrites the tag without knowing the new digest, and a digest left beside a
  # tag it was never resolved from is worse than no digest at all — so the
  # catalogue drops it the moment the two disagree, and it returns when this
  # generator next asks.
  printf '  "%s": { architectures: %s%s },\n' "$key" "$arches" \
    "$([ -n "$digest" ] && printf ", digest: '%s', ref: '%s'" "$digest" "$ref")"
}
export -f inspect_one

# Assemble the SPDX tags from parts so this generator does not itself read as
# carrying a second license declaration (REUSE scans it for SPDX tags).
spdx_copyright='SPDX-FileCopyrightText'
spdx_license='SPDX-License-Identifier'

{
  printf '// %s: The kurly Authors\n' "$spdx_copyright"
  printf '// %s: 0BSD\n' "$spdx_license"
  echo "//"
  echo "// Generated by gen-architectures — DO NOT EDIT. What each stage's pinned"
  echo "// image resolves to right now: the linux CPU architectures it publishes, and"
  echo "// the digest its tag currently points at. Rerun gen-architectures after an"
  echo "// image bump; check-catalog fails on a missing entry."
  echo "{"
  git ls-files 'workloads/*/*.image' | xargs -P8 -I{} bash -c 'inspect_one "$@"' _ {} | LC_ALL=C sort
  echo "}"
} >"$out"

# The file is a catalog/*.libsonnet like any other, so check-fmt formats it too.
jsonnetfmt --in-place "$out"

echo "wrote $out ($(grep -c ': {' "$out") stages, $(grep -c 'digest:' "$out") with a digest)"
