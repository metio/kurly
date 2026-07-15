#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the valkey workload: the persistent StatefulSet instance AND the
# zero-downtime cache (Deployment + primary-following Service + labeler sidecar).
# For the cache, wait for the rollout AND for the primary Service to gain an
# endpoint — proving the labeler promoted the sole pod to primary. No operator.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

echo "== valkey persistent instance (StatefulSet) =="
ns=kurly-valkey-instance
kurly::namespace "$ns"
kurly::render workloads/valkey/instance.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-
if ! kubectl --namespace="$ns" rollout status statefulset/valkey --timeout=300s; then
  kurly::diagnose "$ns"
  exit 1
fi

echo "== valkey zero-downtime cache (Deployment + primary-following Service) =="
ns=kurly-valkey-cache
kurly::namespace "$ns"
kurly::render workloads/valkey/cache.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-
if ! kubectl --namespace="$ns" rollout status deployment/valkey --timeout=300s; then
  kurly::diagnose "$ns"
  exit 1
fi

# The primary-following `valkey` Service (labeler sidecar + RBAC) is part of the
# cache; where present, wait for it to gain an endpoint — proving the labeler
# promoted the sole pod to primary.
if kubectl --namespace="$ns" get service valkey >/dev/null 2>&1; then
  echo "== wait for the primary Service to get an endpoint (labeler promoted the master) =="
  addr=""
  for _ in $(seq 1 30); do
    addr="$(kubectl --namespace="$ns" get endpoints valkey -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
    [ -n "$addr" ] && break
    sleep 3
  done
  if [ -z "$addr" ]; then
    echo "::error::the primary-following Service never gained an endpoint"
    kurly::diagnose "$ns"
    exit 1
  fi
fi
echo "valkey instance + zero-downtime cache are Ready on a live cluster"
