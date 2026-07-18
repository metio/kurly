#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the prometheus workload: install the prometheus-operator, apply the CR
# and its scrape RBAC, and prove the two things the render gates cannot — that the
# operator reconciles the CR into a running Prometheus, and that Prometheus
# actually SCRAPES. A Prometheus that comes up but cannot discover or read a
# target is useless, and only a cluster shows the RBAC and the selectors are right.
#
# Three assertions:
#   1. The operator reconciles the CR into a Ready StatefulSet.
#   2. Given a ServiceMonitor, Prometheus discovers the target and scrapes it —
#      `up == 1` for it, queried from Prometheus's own API. This exercises the
#      cluster RBAC (discovery) and the select-everything default together.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
OPERATOR_VERSION="v0.92.1"

ns=monitoring
promql="http://prometheus-operated.${ns}.svc:9090/api/v1/query"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::prometheus state"
  kubectl --namespace="$ns" get prometheus,statefulset,servicemonitor,pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get prometheus prometheus -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/name=prometheus --tail=40 2>/dev/null || true
  echo "--- operator log ---"
  kubectl --namespace=default logs --selector=app.kubernetes.io/name=prometheus-operator --tail=40 2>/dev/null || true
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
# Assertion 1 — the operator reconciles the CR into a running Prometheus
# ---------------------------------------------------------------------------

echo "== apply the prometheus workload (kind-sized) =="
# resources and storageSize are parameters (features are rejected on a CR
# workload), so shrink them for the kind node.
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local prometheus = import 'workloads/prometheus/server.libsonnet';
k.list(prometheus(
  namespace='${ns}',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  storageSize='1Gi',
))" | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the operator to create and roll out the StatefulSet =="
# The operator names it prometheus-<cr-name>. It appears a beat after the CR.
appeared=false
for _ in $(seq 1 40); do
  kubectl --namespace="$ns" get statefulset/prometheus-prometheus >/dev/null 2>&1 && { appeared=true; break; }
  sleep 3
done
[ "$appeared" = true ] || fail "the operator never created the Prometheus StatefulSet — check the operator log and the CR status"
kubectl --namespace="$ns" rollout status statefulset/prometheus-prometheus --timeout=300s \
  || fail "the Prometheus StatefulSet never became Ready"

# ---------------------------------------------------------------------------
# Assertion 2 — Prometheus discovers a target and scrapes it
# ---------------------------------------------------------------------------

echo "== give Prometheus a target: a ServiceMonitor for its own metrics =="
# The default selectors match every ServiceMonitor in every namespace, so this is
# picked up with no extra labels; it points at the operator's prometheus-operated
# Service (labelled operated-prometheus=true), whose `web` port serves /metrics.
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: prometheus-self, namespace: ${ns} }
spec:
  selector: { matchLabels: { operated-prometheus: "true" } }
  endpoints: [{ port: web }]
EOF

echo "== a client to query the Prometheus API =="
kubectl --namespace="$ns" run prom-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/prom-client --timeout=120s \
  || fail "the query client pod never became Ready"

echo "== wait for Prometheus to scrape the target (up == 1) =="
# `up` is 1 for a target Prometheus successfully scraped. Its appearance proves
# discovery (the cluster RBAC) plus a completed scrape — the whole read path.
scraped=false
for _ in $(seq 1 40); do
  ups="$(kubectl --namespace="$ns" exec prom-client -- \
    curl -sf "${promql}?query=up" 2>/dev/null \
    | jq -r '[.data.result[]? | select(.value[1] == "1")] | length' 2>/dev/null || echo 0)"
  echo "  targets reporting up=1: ${ups:-0}"
  case "${ups:-0}" in ''|0) ;; *) scraped=true; break ;; esac
  sleep 5
done
[ "$scraped" = true ] || fail "Prometheus never reported a scraped target — discovery (RBAC/selectors) or the scrape itself failed"

echo "prometheus served on a live cluster: the operator reconciled the CR into a Ready StatefulSet, and Prometheus discovered a ServiceMonitor target and scraped it (up == 1) — the cluster RBAC and the select-everything default both work"
