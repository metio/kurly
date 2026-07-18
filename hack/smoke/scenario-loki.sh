#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the loki workload, and for the logs pillar of the o11y story: Grafana
# Loki in microservices mode over object storage. It installs cert-manager (the
# loki-operator webhook needs it), the loki-operator, and the kurly seaweedfs
# workload as the S3 store, then applies the LokiStack and proves the two things
# the render gates cannot — the operator reconciles the CR into a whole running
# microservices topology, and a log line pushed to the distributor is queryable
# back out. That round-trip exercises the write path (distributor -> ingester)
# and the read path (query-frontend -> querier) the operator wired.
#
# Three assertions:
#   1. The operator reconciles the LokiStack to Ready — every component up.
#   2. A log line POSTed to the distributor is accepted.
#   3. Querying it back returns the line — logs flow end to end.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=cert-manager/cert-manager
CERT_MANAGER_VERSION="v1.16.2"
# renovate: datasource=github-releases depName=grafana/loki extractVersion=^operator/(?<version>.+)$
LOKI_OPERATOR_VERSION="v0.10.2"

ns=logging
store_ns=logging
bucket=loki
s3="http://seaweedfs-0.seaweedfs-headless.${store_ns}.svc:8333"
distributor="http://loki-distributor-http.${ns}.svc:3100"
query_frontend="http://loki-query-frontend-http.${ns}.svc:3100"
tenant=kurly

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::loki state"
  kubectl --namespace="$ns" get lokistack,deployment,statefulset,pods -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get lokistack loki -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace=loki-operator logs --selector=app.kubernetes.io/name=loki-operator --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install cert-manager ${CERT_MANAGER_VERSION} (the operator webhook needs it) =="
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl --namespace=cert-manager rollout status deployment/cert-manager-webhook --timeout=180s

echo "== install the loki-operator ${LOKI_OPERATOR_VERSION} =="
# The community overlay stamps everything into the loki-operator namespace but
# does not create it, so its namespaced resources fail until it exists.
kubectl create namespace loki-operator --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "github.com/grafana/loki/operator/config/overlays/community?ref=operator/${LOKI_OPERATOR_VERSION}"
kubectl --namespace=loki-operator rollout status deployment \
  --selector app.kubernetes.io/name=loki-operator --timeout=180s

kurly::vendor
kurly::namespace "$ns"

# ---------------------------------------------------------------------------
# The object store first — Loki does not come up without it.
# ---------------------------------------------------------------------------

echo "== deploy the seaweedfs S3 store and create the bucket =="
kurly::render workloads/seaweedfs/server.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$store_ns" --filename=-
kubectl --namespace="$store_ns" rollout status statefulset/seaweedfs --timeout=300s \
  || fail "the seaweedfs store never became Ready"
kubectl --namespace="$store_ns" run s3-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$store_ns" wait --for=condition=Ready pod/s3-client --timeout=120s \
  || fail "the S3 client pod never became Ready"
kubectl --namespace="$store_ns" exec s3-client -- curl -sf -X PUT "${s3}/${bucket}" >/dev/null 2>&1 \
  || fail "could not create the loki bucket on seaweedfs"

# The object-storage Secret the LokiStack names. SeaweedFS with no identities
# accepts the signed requests, so the credentials are dummy.
kubectl --namespace="$ns" create secret generic loki-storage \
  --from-literal=bucketnames="$bucket" \
  --from-literal=endpoint="$s3" \
  --from-literal=access_key_id=loki \
  --from-literal=access_key_secret=lokisecret \
  --from-literal=region=us-east-1

# ---------------------------------------------------------------------------
# Assertion 1 — the operator reconciles the whole topology to Ready
# ---------------------------------------------------------------------------

echo "== apply the LokiStack (1x.demo, over the seaweedfs store) =="
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import 'workloads/loki/server.libsonnet')(storageSecret='loki-storage', storageClass='standard'))" \
  | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the LokiStack to become Ready =="
# Ready means the operator brought up every component — distributor, ingester,
# querier, query-frontend, compactor, index-gateway, gateway — and each accepted
# the object-storage config, i.e. connected to seaweedfs.
ready=false
for _ in $(seq 1 90); do
  status="$(kubectl --namespace="$ns" get lokistack loki \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  echo "  LokiStack Ready=${status:-<pending>}"
  [ "$status" = "True" ] && { ready=true; break; }
  sleep 10
done
[ "$ready" = true ] || fail "the LokiStack never became Ready — the operator could not bring up the topology or connect to seaweedfs"

# ---------------------------------------------------------------------------
# Assertion 2 + 3 — a log pushed to the distributor is queryable back out
# ---------------------------------------------------------------------------

echo "== a client to push and query logs =="
kubectl --namespace="$ns" run loki-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/loki-client --timeout=120s \
  || fail "the log client pod never became Ready"

echo "== push a log line to the distributor =="
# Loki is multi-tenant, so every request carries a tenant (X-Scope-OrgID). The
# value is [nanosecond-timestamp, line]; the timestamp (host clock, close enough
# to the cluster's) must be within Loki's ingestion window.
line="hello from kurly loki"
ts="$(date +%s)000000000"
push_body="{\"streams\":[{\"stream\":{\"job\":\"kurly-probe\"},\"values\":[[\"${ts}\",\"${line}\"]]}]}"
pushed=false
for _ in $(seq 1 12); do
  if kubectl --namespace="$ns" exec loki-client -- \
    curl -sf -X POST -H 'Content-Type: application/json' -H "X-Scope-OrgID: ${tenant}" \
    --data "$push_body" "${distributor}/loki/api/v1/push" >/dev/null 2>&1; then
    pushed=true
    break
  fi
  echo "  push not accepted yet, retrying"
  sleep 5
done
[ "$pushed" = true ] || fail "the distributor never accepted a log push"

echo "== query the log back from the query-frontend =="
# Poll: ingestion into a queryable state lags the push by a moment.
found=false
for _ in $(seq 1 24); do
  start="$(( $(date +%s) - 3600 ))000000000"
  end="$(date +%s)000000000"
  out="$(kubectl --namespace="$ns" exec loki-client -- \
    curl -sf -G -H "X-Scope-OrgID: ${tenant}" \
    --data-urlencode 'query={job="kurly-probe"}' \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${end}" \
    "${query_frontend}/loki/api/v1/query_range" 2>/dev/null || true)"
  case "$out" in
    *"$line"*) found=true; break ;;
  esac
  echo "  log not queryable yet, retrying"
  sleep 5
done
[ "$found" = true ] || fail "the pushed log never came back from a query — the write or read path is broken"

echo "loki served on a live cluster: the operator reconciled the LokiStack into a Ready microservices topology over the seaweedfs S3 store, and a log line round-tripped distributor -> ingester -> querier — the logs pillar works end to end"
