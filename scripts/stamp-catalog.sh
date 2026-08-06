# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Writes the artifacts a catalogue describes INTO that catalogue, at release
# time, so a consumer that pins the catalogue can name what its facts came from.
#
# The facts are not properties of a workload's source alone — `posture`,
# `storage.pvcs`, `clusterScoped` and `runs` all come from rendering that source
# THROUGH the library, so a library change moves them without re-releasing any
# workload. A catalogue that names only the workload artifact therefore leaves
# the join unnamed, and the join is not merely an audit trail: `posture` decides
# whether a tenant's workload may share a node with a stranger's. Two catalogues
# can name the same workload artifact and disagree about it, both correctly.
# So the library is stamped too.
#
# k8s-libsonnet is RECORDED and deliberately not pinned. kurly tracks upstream
# HEAD on purpose, so that a break there surfaces in CI rather than in somebody's
# cluster; recording which commit a catalogue was rendered against costs nothing,
# changes nothing about that, and turns an unnamed moving part into a named one.
#
# What must never happen: stamping "whatever is newest in the registry". The
# artifact named has to be the one the facts were generated FROM, or the
# catalogue asserts a maturity tier and a stage list against something nothing
# examined — specific, confident and wrong, which is worse than saying nothing.
# So a tag is resolved per workload (this run's version for a unit released in
# it, its newest release tag otherwise) and the digest is resolved from THAT tag.
#
# A workload with no release has no artifact and gets no `artifact` key. That is
# a third of the catalogue today and a real state, not a gap to fill: absent must
# never read as permission to deploy `latest`.
#
#   VERSION    the calver this run publishes
#   RELEASED   space-separated units released in this run ("library" and workload ids)
set -euo pipefail

# .build/catalog.json is a BUILD ARTIFACT with no committed copy, so a fresh
# checkout does not have one — CI included. Producing it here rather than
# failing means a gate depends on the DATA it needs instead of on somebody
# having remembered to render it first, which is exactly the step a CI job
# forgot.
[ -f .build/catalog.json ] || gen-catalog >/dev/null

: "${VERSION:?the release version this run publishes}"
released="${RELEASED:-}"
catalog=.build/catalog.json
registry="${KURLY_REGISTRY:-ghcr.io/metio/kurly}"

# The tag a unit's artifact carries: this run's version when the unit is part of
# it, otherwise the newest tag it already has. A unit with neither has never been
# released.
tag_for() {
  local unit="$1"
  if grep -qw -- "$unit" <<<"$released"; then printf '%s' "$VERSION"; return 0; fi
  git tag --list "${unit}-*" | sed "s/^${unit}-//" | sort --version-sort | tail -1
}

# What that tag resolves to. Asked by TAG rather than by "latest", which is the
# whole point: the digest must belong to the version the facts describe.
digest_for() {
  local image="$1" tag="$2"
  skopeo inspect --retry-times 3 --format '{{.Digest}}' "docker://${image}:${tag}" 2>/dev/null || true
}

stamp="$(mktemp)"
cp "$catalog" "$stamp"

# The library, once, at the top level: a catalogue is one render against one
# library, so a per-workload copy would be N copies of a single fact — the shape
# that drifts.
libtag="$(tag_for library)"
if [ -n "$libtag" ]; then
  libdigest="$(digest_for "$registry" "$libtag")"
  stamped="$(jq --arg image "$registry" --arg tag "$libtag" --arg digest "$libdigest" \
    '.library = ({ image: $image, tag: $tag } + (if $digest == "" then {} else { digest: $digest } end))' "$stamp")"
  printf '%s\n' "$stamped" > "$stamp"
  echo "library: ${libtag} ${libdigest:-<no digest>}"
else
  echo "::warning::the library has never been released; the catalogue names none"
fi

# The k8s-libsonnet commit this catalogue was rendered against, read from the
# lock file jb writes when it vendors HEAD.
lock=jsonnetfile.lock.json
if [ -f "$lock" ]; then
  k8scommit="$(jq --raw-output '.dependencies[] | select(.source.git.remote | test("k8s-libsonnet")) | .version' "$lock" | head -1)"
  if [ -n "$k8scommit" ]; then
    stamped="$(jq --arg commit "$k8scommit" \
      '.k8sLibsonnet = { commit: $commit, pinned: false }' "$stamp")"
    printf '%s\n' "$stamped" > "$stamp"
    echo "k8s-libsonnet: ${k8scommit} (recorded, not pinned)"
  fi
fi

missing=""
for dir in workloads/*/; do
  id="${dir#workloads/}"; id="${id%/}"
  tag="$(tag_for "$id")"
  if [ -z "$tag" ]; then missing="${missing}${id} "; continue; fi
  image="${registry}/workloads/${id}"
  digest="$(digest_for "$image" "$tag")"
  stamped="$(jq --arg id "$id" --arg image "$image" --arg tag "$tag" --arg digest "$digest" \
    '.workloads |= map(if .id == $id then . + { artifact: ({ image: $image, tag: $tag } + (if $digest == "" then {} else { digest: $digest } end)) } else . end)' "$stamp")"
  printf '%s\n' "$stamped" > "$stamp"
done

mv "$stamp" "$catalog"
echo "stamped $(jq '[.workloads[] | select(.artifact)] | length' "$catalog") workload artifacts"
[ -z "$missing" ] || {
  echo "no release yet, so no artifact named (a consumer must read this as 'cannot deploy reproducibly', never as 'deploy latest'):"
  printf '%s\n' "$missing" | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' -
}
exit 0
