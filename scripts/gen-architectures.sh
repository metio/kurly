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
  local img="$1" key ref raw arches
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
  # skopeo refuses a reference that carries BOTH a tag and a digest — the very
  # shape every pin here has since images became digest-pinned. It fails on
  # every image, the run falls back to what it derived last time, and the file
  # looks freshly written while saying nothing new. So the tag is dropped and
  # the digest kept: the digest is what identifies the bits anyway.
  local inspectRef="$ref"
  case "$ref" in
    *@sha256:*)
      local namePart="${ref%@*}" digestPart="${ref#*@}"
      # Strip the tag only when the last colon really introduces one — a
      # registry port (host:5000/name@sha256:…) has a slash after its colon.
      case "${namePart##*/}" in *:*) namePart="${namePart%:*}" ;; esac
      inspectRef="${namePart}@${digestPart}"
      ;;
  esac
  raw="$(skopeo inspect --retry-times 3 --raw "docker://${inspectRef}" 2>/dev/null || true)"
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
    arches="$(skopeo inspect --retry-times 3 "docker://${inspectRef}" 2>/dev/null | jq -c '[.Architecture]' 2>/dev/null || printf '["amd64"]')"
  fi
  # The digest this answer is ABOUT, alongside the answer. The reference states
  # its own digest, but that is the reference as it stands now — and Renovate
  # moves it. Recording what was measured lets catalog.jsonnet drop the claim
  # when the pin moves past it, rather than publishing last month's
  # architectures for this month's image.
  local digest="${ref##*@}"
  case "$digest" in sha256:*) ;; *) digest="" ;; esac
  printf '  "%s": { digest: '"'"'%s'"'"', architectures: %s },\n' "$key" "$digest" "$arches"
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
  echo "// Generated by gen-architectures — DO NOT EDIT. The linux CPU architectures"
  echo "// each stage's pinned image publishes, read from its manifest list. Rerun"
  echo "// gen-architectures after an image bump; check-catalog fails on a missing entry."
  echo "{"
  git ls-files 'workloads/*/*.image' | xargs -P8 -I{} bash -c 'inspect_one "$@"' _ {} | LC_ALL=C sort
  echo "}"
} >"$out"

# The file is a catalog/*.libsonnet like any other, so check-fmt formats it too.
jsonnetfmt --in-place "$out"

echo "wrote $out ($(grep -c ': {' "$out") stages)"
