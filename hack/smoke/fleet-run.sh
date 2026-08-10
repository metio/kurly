#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Walks the catalogue on ONE long-lived cluster, one workload at a time.
#
# THE SHAPE, and why each part of it is the way it is:
#
#   ONE CLUSTER, KEPT. Standing a cluster up per run pulls every image again and
#   costs minutes before anything is tested. This host has had three kind
#   clusters alive at once, each holding its own copy of the images and its own
#   provisioner directory — 114GB between them, on a disk that then had 4GB left.
#   One cluster, created if absent, left running afterwards.
#
#   THE DELIVERY STACK, INSTALLED ONCE. Flux, JaaS and stageset are checked for
#   and installed only if missing, so a second run starts testing immediately.
#
#   ONE WORKLOAD AT A TIME. Sequential is not a simplification, it is the
#   requirement: overlapping namespaces exhaust this host's inotify instances at
#   around twenty-five live ones, and the workload that dies from it is the NEXT
#   one, with a file-watcher error that reads exactly like its own bug.
#
#   THE NAMESPACE GOES, AND SO DOES ITS DISK. Deleting the namespace is not
#   enough: local-path removes a volume's directory only when it observes the
#   claim go, and a provisioner that is behind or a volume left Released keeps
#   gigabytes with nothing pointing at them. Every workload is followed by a
#   reconcile of the node's provisioner directory against the volumes that still
#   exist. This is the step whose absence ended the last run.
#
#   RESUMABLE. Four hundred workloads take many hours, so this WILL be
#   interrupted. A stage already measured at the digest it currently pins is
#   skipped, so re-running continues rather than starting over.
#
# CLUSTER    the kind cluster to use (default: kurly)
# WORKLOADS  a space-separated selection instead of the whole catalogue
# REMEASURE  set to 1 to re-run workloads that already have a measurement
# DEEP       set to 1 to also deliver each workload through Flux/JaaS/stageset
set -euo pipefail
cd "$(dirname "$0")/../.."
export KUBERC=/dev/null

# RUN UNDER A CEILING, OR DO NOT RUN. An unbounded walk has taken this host to
# the point of being unusable more than once. The harness re-executes itself
# inside kurly.slice, whose limits are declared in hack/smoke/kurly.slice; the
# node carries its own budget from the kube-cluster wrapper. Set KURLY_NO_SLICE=1
# to opt out, which is for debugging the harness and not for a walk.
if [ "${KURLY_IN_SLICE:-0}" != 1 ] && [ "${KURLY_NO_SLICE:-0}" != 1 ]; then
  units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "${units}/kurly.slice.d"
  cp hack/smoke/kurly.slice "${units}/kurly.slice"
  # The write cap names the WHOLE DISK behind the store. The io controller
  # accounts per block device, so a cap written against the partition the store
  # happens to sit on is accepted in silence and throttles nothing.
  disk="$(findmnt -no SOURCE --target "${HOME}/.local/share" 2>/dev/null || true)"; disk="${disk%%\[*}"
  parent="$(lsblk -no PKNAME "$disk" 2>/dev/null | head -1)"
  [ -n "$parent" ] && disk="/dev/${parent}"
  if [ -b "$disk" ]; then
    printf '[Slice]\nIOReadBandwidthMax=%s 300M\nIOWriteBandwidthMax=%s 150M\n' "$disk" "$disk" \
      > "${units}/kurly.slice.d/disk.conf"
  else
    echo "note: cannot resolve the disk behind the store; the slice carries no bandwidth cap" >&2
    rm -f "${units}/kurly.slice.d/disk.conf"
  fi
  systemctl --user daemon-reload
  echo "== re-executing inside kurly.slice =="
  # PATH and the podman/kube settings are passed explicitly: a transient unit does
  # not necessarily inherit the caller's environment, and a walk that loses the
  # flake tools renders nothing while reporting that it ran.
  exec systemd-run --user --quiet --scope --collect --slice=kurly.slice \
    env KURLY_IN_SLICE=1 HOME="$HOME" PATH="$PATH" KUBERC=/dev/null \
      ${KUBECONFIG:+KUBECONFIG="$KUBECONFIG"} \
      ${CONTAINERS_STORAGE_CONF:+CONTAINERS_STORAGE_CONF="$CONTAINERS_STORAGE_CONF"} \
      ${CONTAINERS_CONF:+CONTAINERS_CONF="$CONTAINERS_CONF"} \
      ${CLUSTER:+CLUSTER="$CLUSTER"} ${WORKLOADS:+WORKLOADS="$WORKLOADS"} \
      ${REMEASURE:+REMEASURE="$REMEASURE"} ${DEEP:+DEEP="$DEEP"} \
      bash "$0" "$@"
fi

# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# The ceiling must be REAL before anything runs. systemd accepts a property it
# cannot enforce (an undelegated controller) without complaint, so the run asks
# the kernel what is actually in force rather than trusting that the unit loaded.
assert_bounded() {
  local cg base miss=""
  cg="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"
  base="$(dirname "$cg")"
  [ -f "${base}/cpu.max" ] && [ "$(cut -d' ' -f1 "${base}/cpu.max")" != max ] || miss="${miss} cpu"
  [ -f "${base}/memory.max" ] && [ "$(cat "${base}/memory.max")" != max ] || miss="${miss} memory"
  if [ -n "$miss" ]; then
    echo "::error::the walk is NOT bounded (no ceiling on:${miss}) — refusing to start" >&2
    echo "the controllers must be delegated to the user manager; check:" >&2
    echo "  cat /sys/fs/cgroup/user.slice/user-\$(id -u).slice/cgroup.controllers" >&2
    exit 1
  fi
  echo "== bounded: cpu.max=$(cat "${base}/cpu.max") memory.max=$(cat "${base}/memory.max") =="
}
assert_bounded

cluster="${CLUSTER:-kurly}"
recorded=catalog/measurements.gen.libsonnet

# The cluster is created with the host's own wrapper, which carries the rootless
# podman configuration this machine needs (an isolated store, fuse-overlayfs, a
# delegated cgroup scope). It runs on the HOST: rootless podman cannot nest a
# user namespace inside nix-portable's sandbox.
ensure_cluster() {
  if kubectl cluster-info >/dev/null 2>&1; then
    echo "== using the cluster the current context points at =="
    return 0
  fi
  command -v kube-cluster >/dev/null 2>&1 || {
    echo "::error::no reachable cluster and no kube-cluster wrapper on PATH" >&2
    exit 1
  }
  echo "== starting kind cluster ${cluster} =="
  # The node's own budget. The wrapper writes these into the container's cgroup
  # and REFUSES to hand over a cluster whose limits did not take effect, so a
  # walk cannot proceed against an unbounded node.
  KUBE_CLUSTER_CPUS=8 KUBE_CLUSTER_MEMORY=14G \
  KUBE_CLUSTER_RBPS=400M KUBE_CLUSTER_WBPS=200M \
    kube-cluster up "$cluster"
  KUBECONFIG="$(kube-cluster kubeconfig "$cluster")"
  export KUBECONFIG
}

# Already measured at the digest this stage pins TODAY. A stage whose image has
# moved since is not skipped: the measurement describes bits that are no longer
# what would be deployed, which is the rule catalog.jsonnet applies when it
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

# THE FILESYSTEM TO ASK ABOUT IS THE ONE HOLDING THE IMAGE STORE, NOT `/`. On an
# ostree host `/` is a composefs image a few megabytes in size and permanently
# 100% full, so a threshold against it fires every iteration and never notices
# the disk that is actually filling — worse than no check, because it reads like
# a working guard.
prune_images() {
  local used node
  used="$(df --output=pcent "${KURLY_STORE_PATH:-$HOME/.local/share}" 2>/dev/null | tail -1 | tr -dc '0-9')"
  [ "${used:-0}" -ge 75 ] || return 0
  node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [ -n "$node" ] || return 0
  echo "== disk at ${used}%, pruning images unused by ${node} =="
  podman exec "$node" crictl rmi --prune >/dev/null 2>&1 || true
}

# ONE CLUSTER, AND ENOUGH ROOM TO FINISH. Checked at the start and every twenty
# workloads, because both failures are silent until they are catastrophic: a
# second cluster left running holds its own copy of every image (three of them
# filled 114GB here), and a disk that reaches zero fails the RUN rather than the
# workload, with container-runtime errors that look like the workload's fault.
check_host() {
  local nodes count free
  # podman on this host needs its storage configuration corrected before it can
  # see its own containers (/home is a symlink to /var/home and the stored path
  # must match textually). Without it the check cannot answer, so it says so
  # rather than reporting one cluster because it found none.
  if [ -z "${CONTAINERS_STORAGE_CONF:-}" ] && [ -f "$HOME/.config/kube-cluster/storage.conf" ]; then
    CONTAINERS_STORAGE_CONF="$(mktemp)"
    sed 's#"/home/#"/var/home/#g' "$HOME/.config/kube-cluster/storage.conf" >"$CONTAINERS_STORAGE_CONF"
    export CONTAINERS_STORAGE_CONF
    [ ! -f "$HOME/.config/kube-cluster/containers.conf" ] || \
      export CONTAINERS_CONF="$HOME/.config/kube-cluster/containers.conf"
  fi
  if nodes="$(podman ps --format '{{.Names}}' 2>/dev/null | grep -- '-control-plane$' || true)"; then
    count="$(printf '%s' "$nodes" | grep -c . || true)"
    if [ "${count:-0}" -gt 1 ]; then
      echo "::error::${count} kind clusters are running — each holds its own images:" >&2
      printf '  %s\n' $nodes >&2
      echo "::error::stop the ones not in use with: kube-cluster down <name>" >&2
    fi
  else
    echo "note: could not ask podman how many clusters are running"
  fi

  free="$(df --output=avail --block-size=G "${KURLY_STORE_PATH:-$HOME/.local/share}" 2>/dev/null | tail -1 | tr -dc '0-9')"
  echo "== disk: ${free:-?}G free =="

  # INOTIFY INSTANCES, WHICH FAIL AS SOMEBODY ELSE'S BUG. Every pod that watches
  # files takes from one host-wide budget (fs.inotify.max_user_instances), and a
  # walk that leaves namespaces behind consumes it steadily. Exhaustion does not
  # report itself: the NEXT workload dies with a file-watcher error of its own —
  # prometheus's config-reloader exits "couldn't initialize inotify: too many open
  # files" and the pod never initializes — which reads exactly like a defect in
  # that workload, and cost a withdrawn e2e claim before it was recognised.
  local inuse limit
  limit="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"
  # `|| true` is load-bearing under `set -euo pipefail`: find walks other users'
  # /proc entries, cannot read them, and exits non-zero even though it printed
  # every answer we asked for. pipefail then propagates that through `wc`, the
  # assignment inherits it, and `set -e` ends the walk here — silently, before
  # this check can report anything. A guard against a silent failure is worth
  # nothing if it fails silently itself.
  inuse="$( (find /proc/*/fd -lname 'anon_inode:inotify' 2>/dev/null || true) | wc -l)"
  if [ "${limit:-0}" -gt 0 ]; then
    echo "== inotify: ${inuse}/${limit} instances in use =="
    if [ "$inuse" -gt $(( limit * 85 / 100 )) ]; then
      # RECLAIM BEFORE GIVING UP. The instances are held by namespaces a previous
      # run — or a scenario run by hand, which cleans up nothing — left behind, and
      # deleting those is exactly the remedy this would otherwise print and exit
      # over. A walk of hundreds of workloads that stops on the first crowded
      # moment finishes nothing.
      echo "== inotify nearly exhausted; reclaiming leftover namespaces =="
      kubectl get ns -o name 2>/dev/null | grep 'namespace/kurly-' | cut -d/ -f2 \
        | xargs -r -n1 -I{} kubectl delete ns {} --wait=false >/dev/null 2>&1 || true
      local waited=0
      while [ "$(kubectl get ns --no-headers 2>/dev/null | grep -c 'kurly-')" -gt 0 ] && [ "$waited" -lt 300 ]; do
        sleep 10; waited=$(( waited + 10 ))
      done
      inuse="$( (find /proc/*/fd -lname 'anon_inode:inotify' 2>/dev/null || true) | wc -l)"
      echo "== inotify after reclaim: ${inuse}/${limit} =="
    fi
    # Still over after reclaiming: the instances belong to something this walk does
    # not own, and continuing would blame the next workloads for a host limit.
    if [ "$inuse" -gt $(( limit * 85 / 100 )) ]; then
      echo "::error::inotify instances are exhausted and reclaiming did not free enough" >&2
      echo "the failure looks like the workload's own file-watcher bug, so stop rather than" >&2
      echo "record false verdicts. Something outside this walk holds them; raise the" >&2
      echo "ceiling on the host (needs root):" >&2
      echo "  sudo sysctl -w fs.inotify.max_user_instances=512" >&2
      exit 1
    fi
  fi
  # Below this a walk cannot finish, and continuing risks the host rather than
  # the run. Stopping leaves everything measured so far on disk, and the walk is
  # resumable, so this costs nothing but the images somebody has to clear.
  if [ -n "$free" ] && [ "$free" -lt 10 ]; then
    echo "::error::only ${free}G free — stopping before the disk does" >&2
    echo "already-measured workloads are recorded; re-run after reclaiming space" >&2
    exit 1
  fi
}

ensure_cluster
check_host
kurly::vendor
kurly::ensure_infrastructure
[ "${DEEP:-0}" != 1 ] || { kurly::install_registry; kurly::publish_images; }

mapfile -t ids < <(
  # Deliberately unquoted: WORKLOADS is a space-separated selection and the
  # split is what turns it into one id per line.
  # shellcheck disable=SC2086
  if [ -n "${WORKLOADS:-}" ]; then printf '%s\n' ${WORKLOADS}
  else jq -r '.workloads[].id' .build/catalog.json | sort
  fi
)

total=${#ids[@]} n=0 booted=0 skipped=0 failed=0
declare -a failures=()
echo "== walking ${total} workloads, one at a time =="

for id in "${ids[@]}"; do
  n=$((n + 1))
  scenario="hack/smoke/scenario-${id}.sh"
  if [ ! -f "$scenario" ]; then
    echo "[${n}/${total}] ${id}: no scenario"; skipped=$((skipped + 1)); continue
  fi
  if measured_already "$id"; then
    echo "[${n}/${total}] ${id}: measured at its current digest"; skipped=$((skipped + 1)); continue
  fi

  echo "[${n}/${total}] ${id}"
  [ $(( (n - 1) % 20 )) -ne 0 ] || [ "$n" -eq 1 ] || check_host
  prune_images
  if bash "$scenario" >"/tmp/fleet-${id}.log" 2>&1; then
    grep -E '^measured:' "/tmp/fleet-${id}.log" || true
    booted=$((booted + 1))
    if [ "${DEEP:-0}" = 1 ]; then
      kurly::deep "$id" || { echo "  delivery failed"; failed=$((failed + 1)); failures+=("${id}:deep"); }
    fi
  else
    echo "  did not boot (see /tmp/fleet-${id}.log)"
    failed=$((failed + 1)); failures+=("$id")
  fi

  # Unconditional, and in this order: the namespace and the workload's
  # cluster-scoped leftovers first, then the disk those volumes were using.
  kurly::cleanup_workload "$id" >/dev/null 2>&1 || true
  kurly::purge_pv_data
done

echo
echo "== booted ${booted}, skipped ${skipped}, failed ${failed} of ${total} =="
[ "${#failures[@]}" -eq 0 ] || echo "did not boot: ${failures[*]}"
echo "fold the measurements into the catalogue with: gen-measurements"
