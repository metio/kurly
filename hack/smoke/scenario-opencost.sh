#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the opencost workload. Like metrics-server it is a cluster add-on: it
# renders the cluster roles it binds and states its own namespace, so it is applied
# as rendered rather than into a per-workload namespace, and awaited where it lands.
# It refuses to start without a Prometheus answering queries, so the scenario stands
# up a throwaway one beside it (kurly's own prometheus workload is a custom resource
# an operator reconciles, which this fast check does not install) and points the
# add-on at that Service.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=opencost
kurly::namespace "$ns"

echo "== provision a throwaway prometheus =="
kubectl --namespace="$ns" apply --filename=- <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: prometheus, labels: { app: prometheus } }
spec:
  replicas: 1
  selector: { matchLabels: { app: prometheus } }
  template:
    metadata: { labels: { app: prometheus } }
    spec:
      containers:
        - name: prometheus
          image: docker.io/prom/prometheus:v3.9.1
          ports: [{ containerPort: 9090 }]
---
apiVersion: v1
kind: Service
metadata: { name: prometheus }
spec:
  selector: { app: prometheus }
  ports: [{ port: 9090, targetPort: 9090 }]
EOF
kubectl --namespace="$ns" rollout status deployment/prometheus --timeout=180s

echo "== boot workloads/opencost/server.libsonnet (cluster add-on) =="
jsonnet -J vendor -e "local k = import 'github.com/metio/kurly/main.libsonnet'; \
  k.list((import 'workloads/opencost/server.libsonnet')(prometheusEndpoint='http://prometheus:9090') + k.hostUsers())" \
  | kubectl apply --filename=-

kurly::await_ready "$ns" deployment/opencost \
  || { echo "::error::opencost never became Ready"; kurly::diagnose "$ns"; exit 1; }
echo "ok: workloads/opencost/server.libsonnet is healthy on a live cluster"
