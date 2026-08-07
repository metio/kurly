#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Walks EVERY catalogued workload's fast scenario to measure what it costs to
# start: seconds to Ready, memory at its startup peak, memory once settled. The
# scenarios record those numbers themselves (kurly::boot), so this file is only
# the walk — which workloads, in what order, and how to survive the length of it.
#
# THE FAST TIER ONLY. Measuring needs the workload booted from its own image and
# nothing else; the deep tier's registry, Flux, JaaS and stageset prove delivery,
# which is a different claim and several times the runtime.
#
# RESUMABLE, AND THAT IS THE POINT. Four hundred workloads take many hours, so
# this run WILL be interrupted — by a full disk, a laptop lid, a kill. A stage
# already measured at the digest it is currently pinned to is skipped, so
# restarting continues rather than starting over, and finishing is a matter of
# running it again until it reports nothing left.
#
# WORKLOADS  a space-separated selection, for re-measuring a few by hand
# REMEASURE  set to 1 to measure everything again, ignoring what is recorded
set -euo pipefail
cd "$(dirname "$0")/../.."
export KUBERC=/dev/null
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

recorded=catalog/measurements.gen.libsonnet

# Already measured at the digest this stage pins TODAY. A stage whose image moved
# since is not skipped: the measurement describes bits that are no longer what
# would be deployed, which is the same rule catalog.jsonnet applies when it
# decides whether to publish the figure at all.
measured_already() {
  local id="$1" stage image digest have
  [ "${REMEASURE:-0}" != 1 ] || return 1
  [ -f "$recorded" ] || return 1
  for stage in "workloads/${id}"/*.libsonnet; do
    [ -e "$stage" ] || return 1
    image="${stage%.libsonnet}.image"
    [ -f "$image" ] || return 1
    digest="$(sed -E 's/.*@(sha256:[0-9a-f]+).*/\1/' "$image")"
    case "$digest" in sha256:*) ;; *) return 1 ;; esac
    have="$(jsonnet "$recorded" 2>/dev/null \
      | jq -r --arg k "${id}/$(basename "$stage" .libsonnet)" '.[$k].digest // ""' 2>/dev/null || true)"
    [ "$have" = "$digest" ] || return 1
  done
  return 0
}

# The node's image store fills up long before the walk ends — one image per
# workload, and this host's is an isolated store on the same filesystem as
# everything else. Pruning what no running pod references costs nothing and is
# the difference between a walk that finishes and a disk with nothing left.
#
# THE FILESYSTEM TO ASK ABOUT IS THE ONE HOLDING THE STORE, NOT `/`. On an ostree
# host `/` is a composefs image a few megabytes in size and permanently 100%
# full, so a check against it fires on every iteration and never notices real
# pressure — which is worse than no check, because it reads like a working guard.
#
# The node name is read from the current context rather than assumed: this host
# has had three kind clusters at once, and pruning a cluster the walk is not
# using frees nothing while leaving the one it is using to fill up.
prune_images() {
  local used node
  used="$(df --output=pcent "${KURLY_STORE_PATH:-$HOME/.local/share}" 2>/dev/null | tail -1 | tr -dc '0-9')"
  [ "${used:-0}" -ge 80 ] || return 0
  node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [ -n "$node" ] || return 0
  echo "== disk at ${used}%, pruning images unused by ${node} =="
  podman exec "$node" crictl rmi --prune >/dev/null 2>&1 || true
}

mapfile -t ids < <(
  # Deliberately unquoted: WORKLOADS is a space-separated selection and the
  # split is what turns it into one id per line.
  # shellcheck disable=SC2086
  if [ -n "${WORKLOADS:-}" ]; then printf '%s\n' ${WORKLOADS}
  else jq -r '.workloads[].id' .build/catalog.json | sort
  fi
)

kurly::vendor

total=${#ids[@]} n=0 done_=0 skipped=0 failed=0
declare -a failures=()
echo "== measuring ${total} workloads =="

for id in "${ids[@]}"; do
  n=$((n + 1))
  scenario="hack/smoke/scenario-${id}.sh"
  if [ ! -f "$scenario" ]; then
    echo "[${n}/${total}] ${id}: no scenario — skipped"
    skipped=$((skipped + 1)); continue
  fi
  if measured_already "$id"; then
    echo "[${n}/${total}] ${id}: already measured at its current digest — skipped"
    skipped=$((skipped + 1)); continue
  fi

  echo "[${n}/${total}] ${id}"
  prune_images
  # Cleanup is unconditional and inside the same iteration: a namespace left
  # behind holds file watchers, and about twenty-five live ones exhaust this
  # host's inotify instances — after which the NEXT workload fails with an error
  # that looks exactly like its own bug.
  if bash "$scenario" >"/tmp/measure-${id}.log" 2>&1; then
    grep -E '^measured:' "/tmp/measure-${id}.log" || true
    done_=$((done_ + 1))
  else
    echo "  did not boot (see /tmp/measure-${id}.log)"
    failed=$((failed + 1)); failures+=("$id")
  fi
  kurly::cleanup_workload "$id" >/dev/null 2>&1 || true
done

echo
echo "== measured ${done_}, skipped ${skipped}, failed ${failed} of ${total} =="
[ "${#failures[@]}" -eq 0 ] || echo "did not boot: ${failures[*]}"
echo "fold the results into the catalogue with: gen-measurements"
