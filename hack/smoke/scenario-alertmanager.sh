#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the alertmanager workload, and for the alerting path it completes: a
# kurly Prometheus wired to a kurly Alertmanager. Installs the prometheus-operator
# and both workloads, points Prometheus's alerting at the Alertmanager through the
# prometheus workload's spec escape, and proves what the render gates cannot — the
# Alertmanager CR reconciles into a running server, and Prometheus actually
# DISCOVERS and CONNECTS to it.
#
# Three assertions:
#   1. The operator reconciles the Alertmanager CR into a Ready StatefulSet.
#   2. Prometheus itself becomes Ready with the alerting config applied.
#   3. Prometheus reports the Alertmanager as an ACTIVE endpoint — read from its
#      own API, proof the alerting path (Prometheus -> alertmanager-operated) is
#      live end to end.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
OPERATOR_VERSION="v0.92.1"

ns=monitoring
promql="http://prometheus-operated.${ns}.svc:9090/api/v1"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::alerting-path state"
  kubectl --namespace="$ns" get alertmanager,prometheus,statefulset,pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get prometheus prometheus -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/name=prometheus --tail=30 2>/dev/null || true
  echo "--- operator log ---"
  kubectl --namespace=default logs --selector=app.kubernetes.io/name=prometheus-operator --tail=30 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install the prometheus-operator ${OPERATOR_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/prometheus-operator/prometheus-operator/releases/download/${OPERATOR_VERSION}/bundle.yaml"
kubectl --namespace=default rollout status deployment/prometheus-operator --timeout=180s

kurly::vendor
kurly::namespace "$ns"

# ---------------------------------------------------------------------------
# Assertion 1 — the Alertmanager CR reconciles into a running server
# ---------------------------------------------------------------------------

echo "== deploy the kurly Alertmanager =="
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import 'workloads/alertmanager/server.libsonnet')())" \
  | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the operator to create and roll out the Alertmanager StatefulSet =="
appeared=false
for _ in $(seq 1 40); do
  kubectl --namespace="$ns" get statefulset/alertmanager-alertmanager >/dev/null 2>&1 && { appeared=true; break; }
  sleep 3
done
[ "$appeared" = true ] || fail "the operator never created the Alertmanager StatefulSet"
kubectl --namespace="$ns" rollout status statefulset/alertmanager-alertmanager --timeout=300s \
  || fail "the Alertmanager never became Ready"

# ---------------------------------------------------------------------------
# Assertion 2 — Prometheus comes up wired at the Alertmanager
# ---------------------------------------------------------------------------

echo "== deploy the kurly Prometheus, its alerting pointed at the Alertmanager =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
k.list((import 'workloads/prometheus/server.libsonnet')(
  namespace='${ns}',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  storageSize='1Gi',
  spec={ alerting: { alertmanagers: [{ namespace: '${ns}', name: 'alertmanager-operated', port: 'web' }] } },
))" | kubectl apply --namespace="$ns" --filename=-

appeared=false
for _ in $(seq 1 40); do
  kubectl --namespace="$ns" get statefulset/prometheus-prometheus >/dev/null 2>&1 && { appeared=true; break; }
  sleep 3
done
[ "$appeared" = true ] || fail "the operator never created the Prometheus StatefulSet"
kubectl --namespace="$ns" rollout status statefulset/prometheus-prometheus --timeout=300s \
  || fail "the Prometheus never became Ready"

# ---------------------------------------------------------------------------
# Assertion 3 — Prometheus discovered and connected to the Alertmanager
# ---------------------------------------------------------------------------

echo "== a client to query the Prometheus API =="
kubectl --namespace="$ns" run alert-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/alert-client --timeout=120s \
  || fail "the query client pod never became Ready"

echo "== wait for Prometheus to report an active Alertmanager =="
# /api/v1/alertmanagers lists the Alertmanager endpoints Prometheus has DISCOVERED
# and can reach; a non-empty activeAlertmanagers is proof the alerting path — the
# Service discovery plus a live connection to alertmanager-operated — works.
connected=false
for _ in $(seq 1 40); do
  active="$(kubectl --namespace="$ns" exec alert-client -- \
    curl -sf "${promql}/alertmanagers" 2>/dev/null \
    | jq -r '.data.activeAlertmanagers | length' 2>/dev/null || echo 0)"
  echo "  active alertmanagers: ${active:-0}"
  case "${active:-0}" in ''|0) ;; *) connected=true; break ;; esac
  sleep 5
done
[ "$connected" = true ] || fail "Prometheus never reported an active Alertmanager — service discovery or the connection to alertmanager-operated failed"

echo "alerting path served on a live cluster: the Alertmanager CR reconciled into a Ready StatefulSet, and Prometheus discovered and connected to it (activeAlertmanagers > 0) — metrics to alerting, end to end"
