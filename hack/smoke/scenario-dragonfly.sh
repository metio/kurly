#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the dragonfly workload, proving the two things that separate Dragonfly
# from the RESP servers it is mistaken for.
#
# Dragonfly answers the same protocol as Valkey, so a client cannot tell them
# apart — but it is not a fork of Valkey or Redis. It runs one io thread per core
# it can SEE, which inside a container is the node's core count rather than the
# pod's CPU limit, and it exits at startup unless maxmemory covers 256MiB per
# thread. Those compound: unpinned on a many-core node it starts a thread per
# core, demands gigabytes, and exits before serving anything, however small its
# CPU limit. The workload pins --proactor_threads for exactly that reason.
#
# The render gates already assert the arithmetic. What only a cluster can show is
# that the pinned configuration actually comes up on a real node — the kind node
# here has more cores than the pod's CPU limit, which is the shape that breaks an
# unpinned Dragonfly.
#
# Three assertions:
#
#   1. It serves. A Dragonfly whose threads outran its memory is not slow, it is
#      absent, so a Ready pod is itself the proof the pinning held.
#   2. It really is thread-pinned on this node — read back from the running
#      server, not from the manifest the render gates already cover.
#   3. It speaks RESP: a SET is readable by GET. That is what makes the workload
#      swappable with valkey for a consumer that only knows an endpoint.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-dragonfly
app=dragonfly
headless=dragonfly-headless

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::dragonfly state"
  kubectl --namespace="$ns" get statefulset,pods -o wide 2>/dev/null || true
  # "There are N threads, so X are required. Exiting..." is how a misconfigured
  # Dragonfly reports itself, and it appears only in the container log.
  kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=${app}" --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

kurly::vendor
kurly::namespace "$ns"

echo "== the node's core count (an unpinned Dragonfly would size itself to this) =="
kubectl get nodes -o jsonpath='{.items[0].status.capacity.cpu}' 2>/dev/null | sed 's/^/  cores: /'
echo

echo "== apply the dragonfly instance =="
# kind-in-CI cannot nest user namespaces, so relax that one knob; every other
# hardening default stays on.
kurly::render workloads/dragonfly/instance.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-

# ---------------------------------------------------------------------------
# Assertion 1 — it serves at all
# ---------------------------------------------------------------------------

echo "== wait for dragonfly to become Ready =="
# A Dragonfly whose threads outran its memory never reaches Ready — it exits
# during startup — so a green rollout is itself the proof that the pinning held.
if ! kubectl --namespace="$ns" rollout status statefulset/${app} --timeout=300s; then
  fail "dragonfly never became ready — check the log for 'threads, so N are required. Exiting'"
fi

# ---------------------------------------------------------------------------
# Assertion 2 — the running server is pinned, not just the manifest
# ---------------------------------------------------------------------------

echo "== assert: dragonfly reports the pinned thread count =="
# Read it back from the server rather than the spec: the render gates already
# check what the manifest says, and the thing worth knowing is what Dragonfly
# decided on a node with more cores than the pod may use.
threads="$(kubectl --namespace="$ns" logs "${app}-0" 2>/dev/null | grep -oE 'Running [0-9]+ io threads' | grep -oE '[0-9]+' | head -1)"
[ -n "$threads" ] || fail "dragonfly never reported its io thread count"
echo "  dragonfly is running ${threads} io threads"
[ "$threads" = "2" ] \
  || fail "dragonfly is running ${threads} io threads, not the 2 the workload pins — it sized itself to the node instead of the pod"

# ---------------------------------------------------------------------------
# Assertion 3 — it speaks RESP
# ---------------------------------------------------------------------------

echo "== a busybox client to speak RESP =="
kubectl --namespace="$ns" run resp-client --image=docker.io/library/busybox:1.37.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/resp-client --timeout=120s \
  || fail "the RESP client pod never became ready"

# The inline RESP protocol: a bare "SET k v" is accepted like any Redis-compatible
# server, which is the whole point of the workload being swappable.
resp() {
  kubectl --namespace="$ns" exec resp-client -- sh -c \
    "printf '$1\r\n' | nc -w 2 ${app}-0.${headless} 6379" 2>/dev/null || true
}

echo "== assert: a SET is readable by GET (the protocol a consumer relies on) =="
out="$(resp 'SET kurly-probe hello')"
case "$out" in
  *OK*) echo "  SET: +OK" ;;
  *) fail "dragonfly did not accept SET (said: '${out:-<nothing>}')" ;;
esac
out="$(resp 'GET kurly-probe')"
case "$out" in
  *hello*) echo "  GET: hello" ;;
  *) fail "dragonfly did not return the value (said: '${out:-<nothing>}')" ;;
esac

echo "dragonfly served on a live cluster: ${threads} io threads as pinned (not the node's $(kubectl get nodes -o jsonpath='{.items[0].status.capacity.cpu}')), and RESP round-trips — a consumer holding an endpoint cannot tell it from valkey"
