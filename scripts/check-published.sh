# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Every workload the catalogue carries must have a published artifact.
#
# A release matrix runs with fail-fast disabled, so one workload's job can fail
# while the other 274 succeed and the run still reads as a release. Nothing then
# says so again: the catalogue keeps listing the workload, its entry looks like
# every other, and a consumer offering it discovers at deploy time that there is
# nothing to pull. volsync was in that state for a week — added in the same
# commit as k8up, which released; volsync's job did not, and the only thing that
# eventually noticed was a consumer resolving digests by hand.
#
# So the claim is checked against the registry rather than against the release
# run's own exit status: what matters is whether the artifact is THERE, not
# whether a job once reported pushing it.
#
# A registry that will NOT answer is not the same as an artifact that is not
# there, and conflating them turns a rate limit into a fleet-wide alarm. Each
# lookup retries, and a workload whose registry stays unreachable is reported
# separately as unchecked — the run still fails, because an unchecked claim is
# not a verified one, but it fails saying which of the two happened.
#
# Network-bound: run it on demand or on a schedule, never in the per-PR gate.
set -uo pipefail

registry="${KURLY_REGISTRY:-ghcr.io/metio/kurly/workloads}"

[ -f .build/catalog.json ] || {
  echo "::error::.build/catalog.json is not there — run gen-catalog first" >&2
  exit 1
}

missing=""
unchecked=""
checked=0

while IFS= read -r id; do
  [ -n "$id" ] || continue
  checked=$((checked + 1))

  # Three attempts with backoff, because a fleet-sized sweep meets a rate limit
  # sooner or later and one refused answer must not be read as an absent
  # artifact. `oras resolve` prints a digest on success; the manifest itself is
  # never fetched, so this costs one HEAD-shaped request per workload.
  digest=""
  refused=0
  for delay in 0 5 20; do
    [ "$delay" = 0 ] || sleep "$delay"
    if digest="$(oras resolve "${registry}/${id}:latest" 2>/dev/null)" && [ -n "$digest" ]; then
      break
    fi
    # Tell "this repository does not exist" from "the registry would not talk to
    # us". Only the first is a missing release; the second is a failed question.
    if oras repo tags "${registry}/${id}" >/dev/null 2>&1; then
      refused=1
    fi
    digest=""
  done

  if [ -n "$digest" ]; then
    continue
  elif [ "$refused" = 1 ]; then
    unchecked="${unchecked}${id} "
  else
    missing="${missing}${id} "
  fi
done < <(jq -r '.workloads[].id' .build/catalog.json)

echo "checked ${checked} workloads against ${registry}"

status=0
[ -n "$missing" ] && {
  echo "::error::carried in the catalogue but NOT published — their release never landed:"
  printf '%s\n' "$missing" | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' -
  echo "::error::force-release each with: Actions -> Release -> unit=<id>"
  status=1
}
[ -n "$unchecked" ] && {
  echo "::error::the registry would not answer for these — asked, not answered:"
  printf '%s\n' "$unchecked" | tr ' ' '\n' | grep -v '^$' | sort | paste -sd' ' -
  status=1
}
[ "$status" = 0 ] && echo "every catalogued workload has a published artifact"
exit "$status"
