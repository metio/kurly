#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the cnpg-cluster workload: install the CloudNativePG operator, render a
# single-instance cluster (kind-sized), apply it, and wait for the operator to
# report the PostgreSQL cluster healthy — proving the CR reconciles end to end.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.24.1"

echo "== install the CloudNativePG operator ${CNPG_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml"
kubectl --namespace=cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s

kurly::vendor
ns=kurly-cnpg
kurly::namespace "$ns"

echo "== apply a single-instance PostgreSQL cluster =="
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import 'workloads/cnpg-cluster/cluster.libsonnet')(instances=1, storageSize='256Mi'))" \
  | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the PostgreSQL cluster to become healthy =="
healthy=false
for _ in $(seq 1 72); do
  phase="$(kubectl --namespace="$ns" get cluster postgres -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "cluster phase: ${phase:-<pending>}"
  case "$phase" in *healthy*) healthy=true; break ;; esac
  sleep 5
done
if [ "$healthy" != true ]; then
  kurly::diagnose "$ns"
  kubectl --namespace="$ns" get cluster postgres -o yaml 2>/dev/null | tail -50 || true
  exit 1
fi
echo "the CNPG PostgreSQL cluster is healthy on a live cluster"
