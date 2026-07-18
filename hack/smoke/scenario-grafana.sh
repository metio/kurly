#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the grafana workload, and for the o11y PAIRING it exists to make: a
# kurly Grafana visualising a kurly Prometheus, with no wiring beyond the default
# datasource. It stands up both operators and both workloads, then proves the
# three things the render gates cannot — the Grafana CR reconciles into a running
# server, the Prometheus datasource is imported into it, and Grafana can actually
# REACH that Prometheus.
#
# Three assertions:
#   1. The grafana-operator reconciles the CR into a Ready Deployment.
#   2. The default GrafanaDatasource is imported into Grafana (the instanceSelector
#      matched and the operator applied it) — read from Grafana's own API.
#   3. Grafana's datasource health check against the kurly Prometheus is OK — the
#      pairing works end to end.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
PROMETHEUS_OPERATOR_VERSION="v0.92.1"
# renovate: datasource=github-releases depName=grafana/grafana-operator
GRAFANA_OPERATOR_VERSION="v5.24.0"

ns=monitoring
grafana_api="http://grafana-service.${ns}.svc:3000"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::grafana + prometheus state"
  kubectl --namespace="$ns" get grafana,grafanadatasource,prometheus,deployment,statefulset,pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get grafanadatasource grafana-prometheus -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=grafana-operator --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install the prometheus-operator ${PROMETHEUS_OPERATOR_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/prometheus-operator/prometheus-operator/releases/download/${PROMETHEUS_OPERATOR_VERSION}/bundle.yaml"
kubectl --namespace=default rollout status deployment/prometheus-operator --timeout=180s

kurly::vendor
kurly::namespace "$ns"

echo "== install the grafana-operator ${GRAFANA_OPERATOR_VERSION} =="
# Installed into the target namespace so it reconciles objects there whether it
# is cluster- or namespace-scoped. The helm chart's SemVer drops the release
# tag's leading 'v' (chart 5.24.0 == operator v5.24.0), so strip it.
helm upgrade --install grafana-operator oci://ghcr.io/grafana/helm-charts/grafana-operator \
  --version "${GRAFANA_OPERATOR_VERSION#v}" --namespace "$ns" --wait --timeout 5m
kubectl --namespace="$ns" rollout status deployment \
  --selector app.kubernetes.io/name=grafana-operator --timeout=180s || true

# ---------------------------------------------------------------------------
# Deploy the Prometheus the datasource will point at, then Grafana.
# ---------------------------------------------------------------------------

echo "== deploy the kurly Prometheus (kind-sized) =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
k.list((import 'workloads/prometheus/server.libsonnet')(
  namespace='${ns}',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  storageSize='1Gi',
))" | kubectl apply --namespace="$ns" --filename=-
appeared=false
for _ in $(seq 1 40); do
  kubectl --namespace="$ns" get statefulset/prometheus-prometheus >/dev/null 2>&1 && { appeared=true; break; }
  sleep 3
done
[ "$appeared" = true ] || fail "the operator never created the Prometheus StatefulSet"
kubectl --namespace="$ns" rollout status statefulset/prometheus-prometheus --timeout=300s \
  || fail "the Prometheus never became Ready"

echo "== deploy the kurly Grafana, pointing its datasource at that Prometheus =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
k.list((import 'workloads/grafana/server.libsonnet')(
  prometheusUrl='http://prometheus-operated.${ns}.svc:9090',
))" | kubectl apply --namespace="$ns" --filename=-

# ---------------------------------------------------------------------------
# Assertion 1 — the operator reconciles the CR into a running Grafana
# ---------------------------------------------------------------------------

echo "== wait for the operator to create and roll out the Grafana Deployment =="
appeared=false
for _ in $(seq 1 40); do
  kubectl --namespace="$ns" get deployment/grafana-deployment >/dev/null 2>&1 && { appeared=true; break; }
  sleep 3
done
[ "$appeared" = true ] || fail "the grafana-operator never created the Grafana Deployment — check the CR status and the operator log"
kubectl --namespace="$ns" rollout status deployment/grafana-deployment --timeout=300s \
  || fail "the Grafana Deployment never became Ready"

echo "== read the operator-generated admin credentials =="
user="$(kubectl --namespace="$ns" get secret grafana-admin-credentials -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' 2>/dev/null | base64 -d)"
pass="$(kubectl --namespace="$ns" get secret grafana-admin-credentials -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)"
[ -n "$user" ] && [ -n "$pass" ] || fail "the operator did not mint admin credentials in grafana-admin-credentials"

echo "== a client to query the Grafana API =="
kubectl --namespace="$ns" run grafana-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/grafana-client --timeout=120s \
  || fail "the query client pod never became Ready"

gcurl() { kubectl --namespace="$ns" exec grafana-client -- curl -sf -u "${user}:${pass}" "$@" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Assertion 2 — the Prometheus datasource is imported into Grafana
# ---------------------------------------------------------------------------

echo "== wait for the Prometheus datasource to appear in Grafana =="
uid=""
for _ in $(seq 1 40); do
  uid="$(gcurl "${grafana_api}/api/datasources/name/Prometheus" | jq -r '.uid // empty' 2>/dev/null || true)"
  [ -n "$uid" ] && { echo "  datasource imported, uid=${uid}"; break; }
  sleep 5
done
[ -n "$uid" ] || fail "the Prometheus datasource never appeared in Grafana — the operator import or the instanceSelector failed"

# ---------------------------------------------------------------------------
# Assertion 3 — Grafana can reach that Prometheus (the pairing works)
# ---------------------------------------------------------------------------

echo "== wait for Grafana's datasource health check to pass =="
# Grafana proxies a probe to the datasource URL; OK means it reached the kurly
# Prometheus's prometheus-operated Service — the pairing, end to end.
healthy=false
for _ in $(seq 1 40); do
  status="$(gcurl "${grafana_api}/api/datasources/uid/${uid}/health" | jq -r '.status // empty' 2>/dev/null || true)"
  echo "  datasource health: ${status:-<pending>}"
  [ "$status" = "OK" ] && { healthy=true; break; }
  sleep 5
done
[ "$healthy" = true ] || fail "Grafana never reported the Prometheus datasource healthy — it could not reach prometheus-operated"

echo "grafana served on a live cluster: the operator reconciled the CR into a Ready Deployment, the default Prometheus datasource was imported, and Grafana's health check reached the kurly Prometheus — the o11y pairing works end to end"
