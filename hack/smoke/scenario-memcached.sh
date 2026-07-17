#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the memcached workload, proving the property memcached has instead of
# the one valkey has. The valkey cache survives a version change with its dataset
# intact, because it can replicate. memcached cannot replicate and cannot
# persist, so every upgrade starts cold — what it offers is BOUNDED loss, and
# that is what this scenario measures.
#
# Clients shard memcached themselves, consistent-hashing each key over the
# server list, so the contract rests entirely on the names in that list holding
# still. The workload is a StatefulSet for exactly that reason (its storage is
# nothing; its identity is everything), and the same workload authored as a
# Deployment would render near-identical manifests while behaving completely
# differently: fresh random pod names on every roll, every name in the ring
# changing at once, the WHOLE cache invalidated rather than 1/N of it. No schema
# check, policy, or render test can see that difference — it only exists on a
# live roll, which is why this scenario exists.
#
# Four assertions across one upgrade:
#
#   1. The keys are readable BEFORE the roll. Without this the loss assertion
#      below would pass against a cache that never stored anything.
#   2. At no point are two of the three shards down: a StatefulSet replaces one
#      pod at a time, so a client loses 1/N and keeps N-1.
#   3. The pod names are unchanged afterwards, while their UIDs are not — the
#      pods really were replaced, and the client's ring still points at the same
#      names. A Deployment fails this.
#   4. Every key is gone. memcached loses its data on an upgrade BY DESIGN, and
#      asserting it keeps anyone from mistaking this for the valkey cache.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-memcached
app=memcached
headless=memcached-headless
replicas=3

# The ladder is the two newest published patches, discovered at run time so the
# walk stays current with no edits here. memcached ships only 1.6.x patches, so
# there is no major hop to make — the version moving at all is enough to force
# the roll this scenario measures.
compute_ladder() {
  for p in 1 2; do
    curl -fsSL "https://hub.docker.com/v2/repositories/library/memcached/tags?page_size=100&page=${p}" 2>/dev/null || true
  done | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u -V | tail -2
}

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::memcached state"
  kubectl --namespace="$ns" get statefulset,pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get pods -o jsonpath='{range .items[*]}{.metadata.name}{" uid="}{.metadata.uid}{" image="}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

mapfile -t LADDER < <(compute_ladder)
[ "${#LADDER[@]}" -eq 2 ] || fail "could not discover two memcached patch versions (got: ${LADDER[*]:-none})"
FROM="${LADDER[0]}"
TO="${LADDER[1]}"
echo "memcached ladder (dynamic): ${FROM} -> ${TO}"

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# How many memcached pods report Ready right now.
ready_count() {
  kubectl --namespace="$ns" get pods --selector="app.kubernetes.io/name=${app}" -o json 2>/dev/null \
    | jq '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

# The pod names, sorted — the client's hash ring, as the cluster sees it.
pod_names() {
  kubectl --namespace="$ns" get pods --selector="app.kubernetes.io/name=${app}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort | tr '\n' ' '
}

# name=uid pairs, sorted — identity AND instance, so a roll can be told from a
# no-op.
pod_uids() {
  kubectl --namespace="$ns" get pods --selector="app.kubernetes.io/name=${app}" \
    -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.uid}{"\n"}{end}' 2>/dev/null | sort | tr '\n' ' '
}

# mc <pod-ordinal> <protocol-command> — speak the memcached text protocol to one
# pod by its STABLE DNS name, from a busybox client in the same namespace. The
# memcached image ships nothing that can speak its own protocol, so the client
# lives in its own pod rather than being exec'd into the server.
mc() {
  local ordinal="$1" cmd="$2"
  kubectl --namespace="$ns" exec mc-client -- sh -c \
    "printf '${cmd}\r\n' | nc -w 2 ${app}-${ordinal}.${headless} 11211" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------

kurly::vendor
kurly::namespace "$ns"

echo "== apply the memcached cache at ${FROM} (StatefulSet + headless Service) =="
# kind-in-CI cannot nest user namespaces, so relax that one knob; every other
# hardening default stays on.
kurly::render workloads/memcached/cache.libsonnet \
  "+ k.hostUsers() + k.image('docker.io/library/memcached:${FROM}')" \
  | kubectl apply --namespace="$ns" --filename=-

echo "== wait for all ${replicas} shards =="
if ! kubectl --namespace="$ns" rollout status statefulset/${app} --timeout=300s; then
  fail "the memcached StatefulSet never became ready"
fi

echo "== a busybox client to speak the memcached protocol =="
kubectl --namespace="$ns" run mc-client --image=docker.io/library/busybox:1.37.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/mc-client --timeout=120s \
  || fail "the memcached client pod never became ready"

# ---------------------------------------------------------------------------
# Assertion 1 — the keys are really there
# ---------------------------------------------------------------------------

echo "== write one key into each shard, addressed by its stable name =="
for i in $(seq 0 $((replicas - 1))); do
  out="$(mc "$i" "set shard-key 0 0 6\r\nvalue${i}")"
  case "$out" in
    *STORED*) echo "  ${app}-${i}: stored" ;;
    *) fail "${app}-${i} did not store its key (protocol said: '${out:-<nothing>}')" ;;
  esac
done

# The loss assertion at the end is worth nothing unless the data was provably
# there first: a cache that stored nothing loses nothing, and the run would go
# green having tested no memcached behaviour at all.
echo "== assert: every key reads back BEFORE the roll =="
for i in $(seq 0 $((replicas - 1))); do
  out="$(mc "$i" "get shard-key")"
  case "$out" in
    *"value${i}"*) echo "  ${app}-${i}: reads back value${i}" ;;
    *) fail "${app}-${i} did not return its key before the roll (got: '${out:-<nothing>}') — the loss assertion would be vacuous" ;;
  esac
done

names_before="$(pod_names)"
uids_before="$(pod_uids)"
echo "ring before: ${names_before}"

# ---------------------------------------------------------------------------
# Assertion 2 — at most one shard down at a time
# ---------------------------------------------------------------------------

# Sample the Ready count throughout the roll and keep the minimum. A poll after
# the fact would only ever see a settled cluster, which is why this runs
# alongside the roll rather than around it.
minfile="$(mktemp)"
flagfile="$(mktemp)"
echo "$replicas" > "$minfile"
(
  while [ -f "$flagfile" ]; do
    n="$(ready_count)"
    m="$(cat "$minfile")"
    if [ "$n" -lt "$m" ]; then echo "$n" > "$minfile"; fi
    sleep 1
  done
) &
sampler=$!

echo "== roll ${FROM} -> ${TO} =="
kurly::render workloads/memcached/cache.libsonnet \
  "+ k.hostUsers() + k.image('docker.io/library/memcached:${TO}')" \
  | kubectl apply --namespace="$ns" --filename=-

if ! kubectl --namespace="$ns" rollout status statefulset/${app} --timeout=300s; then
  rm -f "$flagfile"; wait "$sampler" 2>/dev/null || true
  fail "the roll to ${TO} never completed"
fi

rm -f "$flagfile"
wait "$sampler" 2>/dev/null || true
min_ready="$(cat "$minfile")"
rm -f "$minfile"
echo "fewest shards Ready at any sample: ${min_ready}/${replicas}"

# Three outcomes, and only one of them is a pass:
#   < replicas-1 : more than one shard was down — a client would lose more than
#                  the 1/N a StatefulSet is supposed to cost it.
#   = replicas   : the sampler never caught a restart, so nothing was measured.
#                  Passing here would be a green that tested nothing, which is
#                  worse than failing.
#   = replicas-1 : exactly one shard down at a time, as intended.
if [ "$min_ready" -lt "$((replicas - 1))" ]; then
  fail "only ${min_ready}/${replicas} shards were Ready during the roll — more than one shard went down at once"
elif [ "$min_ready" -eq "$replicas" ]; then
  fail "never observed a shard restart (${min_ready}/${replicas} Ready throughout) — the roll was not measured, so this proves nothing"
fi
echo "exactly one shard was down at a time — a client keeps $((replicas - 1))/${replicas} of its ring"

# ---------------------------------------------------------------------------
# Assertion 3 — stable names, new instances
# ---------------------------------------------------------------------------

echo "== assert: the ring is unchanged, but the pods are new =="
names_after="$(pod_names)"
uids_after="$(pod_uids)"

[ "$names_before" = "$names_after" ] \
  || fail "the pod names changed across the roll ('${names_before}' -> '${names_after}') — a client's hash ring would reshuffle and drop the whole cache"
[ "$uids_before" != "$uids_after" ] \
  || fail "the pod UIDs are unchanged — nothing was actually replaced, so the roll did not happen"
echo "ring after:  ${names_after} (same names, new pods)"

img="$(kubectl --namespace="$ns" get statefulset ${app} -o jsonpath='{.spec.template.spec.containers[0].image}')"
case "$img" in
  *"${TO}"*) echo "shards now run ${img}" ;;
  *) fail "the StatefulSet did not roll to ${TO} (image is ${img})" ;;
esac

# ---------------------------------------------------------------------------
# Assertion 4 — the cache is cold, by design
# ---------------------------------------------------------------------------

# Stated as an assertion rather than left implied: memcached cannot hand its
# dataset to the new version, and a reader who has seen the valkey cache will
# reasonably assume otherwise.
echo "== assert: every key is gone (memcached upgrades cold) =="
for i in $(seq 0 $((replicas - 1))); do
  out="$(mc "$i" "get shard-key")"
  case "$out" in
    *"value${i}"*) fail "${app}-${i} still holds its key after the roll — memcached cannot preserve data across a restart, so this scenario is measuring something other than it believes" ;;
    *) echo "  ${app}-${i}: cold, as expected" ;;
  esac
done

echo "memcached kept its ring and lost its data: one shard down at a time, names stable, cache cold — the upgrade cost a client 1/${replicas} at a time and nothing more"
