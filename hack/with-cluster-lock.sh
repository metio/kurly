#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Runs a command holding an exclusive lock on the local kind cluster.
#
#     hack/with-cluster-lock.sh bash hack/smoke/scenario-<id>.sh
#
# Authoring a workload is CPU-bound and parallelises fine; booting one does not.
# Several scenarios against one cluster collide in ways that look like the
# workload's own failure rather than a collision: a scenario deletes cluster-
# scoped objects another is relying on (bollwerk's admission policies govern
# everything booted after them, a stale metrics.k8s.io APIService breaks
# namespace deletion cluster-wide), and the node's inotify instances run out at
# roughly twenty-five live namespaces, after which the NEXT workload dies with a
# file-watcher error that reads exactly like its own bug.
#
# So the cluster is a semaphore of one. Everything else — rendering, kubeconform,
# the catalogue generators — runs concurrently and takes no lock.
#
# HOLD IT FOR THE WHOLE SCENARIO, not for each command. The unit that must not
# overlap is apply-wait-verify-DELETE, because what collides is the namespace
# EXISTING, not the kubectl call that creates it. Wrapping each command
# separately looks like it serializes and does not: the lock is released while
# the namespace is still up, the next runner takes it immediately, and both
# workloads sit on the node together. Three did exactly that here — the node ran
# out of user namespaces (`fork/exec /proc/self/exe: operation not permitted` on
# every sandbox) and the storage provisioner crashlooped, so three workloads were
# reported unproven for reasons none of them caused.
#
#   RIGHT:  with-cluster-lock.sh bash hack/smoke/scenario-x.sh
#   RIGHT:  with-cluster-lock.sh bash -c 'kubectl apply …; kubectl wait …; kubectl delete ns …'
#   WRONG:  with-cluster-lock.sh kubectl apply …
#           with-cluster-lock.sh kubectl wait …      # the gap between these is
#           with-cluster-lock.sh kubectl delete ns … # where the collision lives
#
# The lock is advisory and cooperative: it only works because every cluster user
# takes it. A scenario run directly still bypasses it, which is fine for one
# person at a terminal and wrong for a fan-out.
set -euo pipefail

lock="${KURLY_CLUSTER_LOCK:-${TMPDIR:-/tmp}/kurly-cluster.lock}"
# The timeout is generous rather than absent: a holder that wedges should
# eventually let the queue fail with a message naming the lock, instead of
# leaving every waiter blocked forever with no output.
timeout_seconds="${KURLY_CLUSTER_LOCK_TIMEOUT:-3600}"

[ $# -gt 0 ] || {
  echo "usage: $0 <command> [args...]" >&2
  exit 2
}

# The file must exist before flock can hold a descriptor on it, and it is never
# removed: deleting it would let a waiter create a NEW file and lock that one
# instead, so two runners would each hold "the" lock.
: >>"$lock"

exec 9>>"$lock"
if ! flock --exclusive --timeout "$timeout_seconds" 9; then
  echo "::error::timed out after ${timeout_seconds}s waiting for the cluster lock (${lock})" >&2
  exit 1
fi

echo "== cluster lock held by $$: $* ==" >&2
"$@"
