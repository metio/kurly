#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the SPLIT seaweedfs — the master/volume/filer stages deployed together.
# The render gates confirm each manifest; only a cluster shows the three actually
# form a working store, and the one thing that most easily goes wrong on
# Kubernetes: a volume server must register with the master under a ROUTABLE
# address, or the master hands clients an unreachable one and every read fails.
#
# Three assertions, each proving a link the render gates cannot:
#   1. The master, the volume tier (2 servers), and the filer all become Ready.
#   2. The volume servers REGISTER with the master — proof the pod-IP advertising
#      worked, read straight from the master's topology.
#   3. An object PUT through the filer's S3 gateway reads back byte-for-byte —
#      the whole path (client → filer → master → volume, over routable IPs) serves.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-seaweedfs-dist
master_http="http://seaweedfs-master-0.seaweedfs-master-headless.${ns}.svc:9333"
filer_s3="http://seaweedfs-filer-0.seaweedfs-filer-headless.${ns}.svc:8333"
content='hello from a distributed seaweed'

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::split seaweedfs state"
  kubectl --namespace="$ns" get statefulset,pods -o wide 2>/dev/null || true
  echo "--- master topology (where volume registration shows) ---"
  kubectl --namespace="$ns" exec s3-client -- curl -sf "${master_http}/dir/status" 2>/dev/null || true
  echo
  for role in master volume filer; do
    echo "--- ${role} log ---"
    kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=seaweedfs-${role}" --tail=40 2>/dev/null || true
  done
  echo "::endgroup::"
  exit 1
}

kurly::vendor
kurly::namespace "$ns"

# kind-in-CI cannot nest user namespaces, so relax that one knob on each stage;
# every other hardening default stays on.
apply() { kurly::render "workloads/seaweedfs/$1.libsonnet" "+ k.hostUsers()" | kubectl apply --namespace="$ns" --filename=-; }

# ---------------------------------------------------------------------------
# Assertion 1 — the three tiers come up (master first, so peers can find it)
# ---------------------------------------------------------------------------

echo "== deploy the master =="
apply master
kubectl --namespace="$ns" rollout status statefulset/seaweedfs-master --timeout=180s \
  || fail "the master never became Ready"

echo "== deploy the volume tier and the filer =="
apply volume
apply filer
kubectl --namespace="$ns" rollout status statefulset/seaweedfs-volume --timeout=300s \
  || fail "the volume tier never became Ready"
kubectl --namespace="$ns" rollout status statefulset/seaweedfs-filer --timeout=300s \
  || fail "the filer never became Ready"

echo "== a curl client =="
kubectl --namespace="$ns" run s3-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/s3-client --timeout=120s \
  || fail "the client pod never became Ready"

# ---------------------------------------------------------------------------
# Assertion 2 — the volume servers registered with the master
# ---------------------------------------------------------------------------

echo "== wait for the volume servers to register with the master =="
# Topology.Max is the sum of each registered server's volume slots (-max); it is
# 0 until a volume server has registered, so a positive value is the master
# confirming the pod-IP advertising reached it. Registration lags Ready by a beat.
registered=false
for _ in $(seq 1 40); do
  maxvol="$(kubectl --namespace="$ns" exec s3-client -- \
    curl -sf "${master_http}/dir/status" 2>/dev/null | jq -r '.Topology.Max // 0' 2>/dev/null || echo 0)"
  echo "  registered volume capacity: ${maxvol:-0}"
  case "${maxvol:-0}" in ''|0) ;; *) registered=true; break ;; esac
  sleep 3
done
[ "$registered" = true ] || fail "no volume server ever registered with the master — check the advertised address"

# ---------------------------------------------------------------------------
# Assertion 3 — the store serves S3 through the filer, end to end
# ---------------------------------------------------------------------------

echo "== create a bucket through the filer's S3 gateway =="
kubectl --namespace="$ns" exec s3-client -- curl -sf -X PUT "${filer_s3}/kurly-probe" >/dev/null 2>&1 \
  || fail "the filer did not create the bucket (S3 gateway not serving?)"

echo "== PUT an object (its data lands on a volume server) =="
kubectl --namespace="$ns" exec s3-client -- \
  curl -sf -X PUT --data-binary "$content" "${filer_s3}/kurly-probe/greeting" >/dev/null 2>&1 \
  || fail "the object PUT failed — the filer could not place data on a volume server"

echo "== GET it back byte-for-byte =="
out="$(kubectl --namespace="$ns" exec s3-client -- curl -sf "${filer_s3}/kurly-probe/greeting" 2>/dev/null || true)"
[ "$out" = "$content" ] \
  || fail "the object did not round-trip (got: '${out:-<nothing>}', wanted: '${content}') — a volume was likely advertised at an unreachable address"

echo "split seaweedfs served on a live cluster: master + 2 volume servers + filer formed a store, the volumes registered under routable pod IPs, and an object round-tripped through the S3 gateway"
