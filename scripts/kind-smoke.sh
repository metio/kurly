# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Applies kurly's rendered output to the current cluster (a kind cluster in CI)
# and waits for it to become Ready — proving the manifests kurly produces are
# not just schema-valid (that is check-security/kubeconform) but actually run.
#
# Only the workloads whose images exist and can start are applied here: the
# nginx examples (a stateless http workload with an Ingress) and the tik
# workload (a stateful one — a PVC that binds WaitForFirstConsumer, a mounted
# ConfigMap, an optional signing-key Secret, a scratch emptyDir, a pinned
# non-root uid, and the Recreate strategy — whose board serves /tickets.edn).
# The example workloads that reference placeholder images (ghcr.io/example/...)
# are rendered and schema-checked by check-examples, not run here.
#
# Expects a reachable cluster (KUBECONFIG set); the workflow owns creating and
# tearing down the kind cluster, so this script runs against any cluster.

jb install

namespace="kurly-smoke"
kubectl create namespace "$namespace" --dry-run=client --output=yaml | kubectl apply --filename=-

# Gateway API standard CRDs so the tik HTTPRoute is accepted. The route is not
# gated on being programmed (no Gateway controller runs here); only the
# workloads' own readiness is awaited below.
kubectl apply --filename=https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
kubectl wait --for=condition=Established --timeout=60s \
  crd/httproutes.gateway.networking.k8s.io

echo "== apply the stateless nginx workload (Deployment + Service + Ingress) =="
jsonnet -J vendor examples/web.jsonnet | kubectl apply --namespace="$namespace" --filename=-

echo "== apply the tik workload backend stage (PVC + ConfigMap + Deployment + Service + HTTPRoute) =="
jsonnet -J vendor workloads/tik/stages.jsonnet | jq '.backend' | kubectl apply --namespace="$namespace" --filename=-

echo "== wait for both workloads to become Available =="
# tik's readiness probe IS GET /tickets.edn on the board port, so a successful
# rollout proves the board is serving — no separate probe needed.
kubectl --namespace="$namespace" rollout status deployment/storefront --timeout=180s
kubectl --namespace="$namespace" rollout status deployment/tik --timeout=300s

echo "kurly's rendered output is Ready on a live cluster"
