#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the seaweedfs workload, proving the one thing that matters about an
# object store and that no manifest check can show: it serves S3.
#
# The workload runs `weed server -s3` — master, volume, filer, and an S3 gateway
# in one process over a PersistentVolume. The render gates confirm the manifest;
# only a cluster shows that the gateway comes up on the volume and actually
# stores and returns objects over the S3 HTTP API. That API is the whole point of
# the workload — it is the endpoint a cnpg-cluster writes its backups to — so the
# assertion is an end-to-end round-trip through it.
#
# Two assertions:
#   1. The StatefulSet becomes Ready — the all-in-one server came up on its PVC.
#   2. An object PUT to a bucket over S3 reads back byte-for-byte — the gateway
#      serves the API a backup target relies on.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-seaweedfs
app=seaweedfs
headless=seaweedfs-headless

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::seaweedfs state"
  kubectl --namespace="$ns" get statefulset,pods,pvc -o wide 2>/dev/null || true
  kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=${app}" --tail=60 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

kurly::vendor
kurly::namespace "$ns"

echo "== apply the seaweedfs server =="
# kind-in-CI cannot nest user namespaces, so relax that one knob; every other
# hardening default stays on.
kurly::render workloads/seaweedfs/server.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-

# ---------------------------------------------------------------------------
# Assertion 1 — the all-in-one server came up on its volume
# ---------------------------------------------------------------------------

echo "== wait for seaweedfs to become Ready =="
# Readiness is the S3 port accepting a connection, so a green rollout means the
# gateway is up over the mounted PVC.
if ! kubectl --namespace="$ns" rollout status statefulset/${app} --timeout=300s; then
  fail "seaweedfs never became Ready — the all-in-one server did not come up on its volume"
fi

# ---------------------------------------------------------------------------
# Assertion 2 — it serves S3: PUT an object, GET it back
# ---------------------------------------------------------------------------

echo "== a curl client to speak S3 =="
kubectl --namespace="$ns" run s3-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/s3-client --timeout=120s \
  || fail "the S3 client pod never became Ready"

# The default configuration serves anonymous access, so an unsigned request is
# accepted — enough to prove the gateway stores and returns objects. A real
# backup target puts credentials in front; that is config, not a serving check.
ep="http://${app}-0.${headless}.${ns}.svc:8333"
content='hello from kurly'

echo "== assert: create a bucket over S3 =="
# curl -f fails on any HTTP >= 400, so a clean exit is the 2xx.
kubectl --namespace="$ns" exec s3-client -- curl -sf -X PUT "${ep}/kurly-probe" >/dev/null 2>&1 \
  || fail "seaweedfs did not create the bucket (S3 gateway not serving?)"

echo "== assert: PUT an object =="
kubectl --namespace="$ns" exec s3-client -- \
  curl -sf -X PUT --data-binary "$content" "${ep}/kurly-probe/greeting" >/dev/null 2>&1 \
  || fail "seaweedfs did not accept the object PUT"

echo "== assert: GET it back byte-for-byte =="
out="$(kubectl --namespace="$ns" exec s3-client -- curl -sf "${ep}/kurly-probe/greeting" 2>/dev/null || true)"
[ "$out" = "$content" ] \
  || fail "the object did not round-trip (got: '${out:-<nothing>}', wanted: '${content}')"

echo "seaweedfs served on a live cluster: the all-in-one server came up on its PVC, and an object round-tripped through the S3 API — the endpoint a cnpg-cluster backs up to"
