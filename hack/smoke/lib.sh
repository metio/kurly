#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Shared helpers for the per-workload e2e scenarios (hack/smoke/scenario-*.sh).
# Each scenario is self-contained: it installs whatever operator it needs, renders
# the workload the way a consumer would, applies it to the current cluster (a kind
# cluster the e2e workflow owns), and waits for it to become healthy — proving the
# manifests kurly produces actually RUN, not just that they schema-validate.
set -euo pipefail

# kurly imports k8s-libsonnet (vendored fresh) and resolves its own canonical
# path through a vendor symlink, exactly as the render gates do.
kurly::vendor() {
  jb install >/dev/null
  mkdir -p vendor/github.com/metio
  ln -sfn ../../.. vendor/github.com/metio/kurly
}

# Renders a workload stage (a function(params) app) to a kind: List, the way a
# consumer's JsonnetSnippet does. Extra Jsonnet composed onto the app is passed as
# $2 (e.g. "+ k.hostUsers()") — kind inside GitHub Actions cannot nest user
# namespaces, so kurly-pod workloads relax that one knob for the smoke.
kurly::render() {
  local stage="$1" extra="${2:-}"
  jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${stage}')() ${extra})"
}

# Creates a namespace idempotently.
kurly::namespace() {
  kubectl create namespace "$1" --dry-run=client --output=yaml | kubectl apply --filename=-
}

# Dumps everything useful about a namespace on failure, grouped in the log.
kurly::diagnose() {
  local ns="$1"
  echo "::group::diagnostics ($ns)"
  kubectl --namespace="$ns" get all,pvc,endpoints 2>/dev/null || true
  kubectl --namespace="$ns" get pods --show-labels 2>/dev/null || true
  kubectl --namespace="$ns" describe pods 2>/dev/null | tail -120 || true
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/managed-by=kurly --all-containers=true --tail=100 2>/dev/null || true
  kubectl --namespace="$ns" get events --sort-by=.lastTimestamp 2>/dev/null | tail -40 || true
  echo "::endgroup::"
}

# Dumps the Flux + JaaS + stageset pipeline objects on failure. The Ready
# condition message of the JsonnetSnippet and the StageSet is where import,
# render, and apply errors surface, so print each one's full status.
kurly::diagnose_pipeline() {
  local ns="$1"
  echo "::group::pipeline diagnostics ($ns)"
  kubectl --namespace="$ns" get gitrepository,ocirepository,jsonnetlibrary,jsonnetsnippet,externalartifact,stageset,stageinventory -o wide 2>/dev/null || true
  echo "--- JsonnetSnippet status ---"
  kubectl --namespace="$ns" get jsonnetsnippet valkey -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" describe jsonnetsnippet valkey 2>/dev/null | tail -40 || true
  echo "--- StageSet status ---"
  kubectl --namespace="$ns" get stageset valkey -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" describe stageset valkey 2>/dev/null | tail -40 || true
  echo "::endgroup::"
}

# Installs the FULL Flux suite (always the latest release) and opens the
# source-controller artifact port cluster-wide. JaaS needs the ExternalArtifact
# kind, which ships in source-controller v1.7.0+ (Flux v2.7.0+).
kurly::install_flux() {
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r .tag_name 2>/dev/null || true)"
  [ -n "$ver" ] && [ "$ver" != "null" ] || ver="v2.7.0"
  echo "== install Flux ${ver} =="
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "https://github.com/fluxcd/flux2/releases/download/${ver}/install.yaml"
  kubectl -n flux-system rollout status deploy/source-controller --timeout=300s

  # Flux's default `allow-egress` NetworkPolicy admits ingress to source-controller
  # only from pods inside flux-system, and `allow-scraping` opens only the metrics
  # port (8080). The artifact HTTP server listens on 9090, so an operator running
  # outside flux-system can't fetch artifacts once the CNI enforces NetworkPolicies
  # (recent kindnet does; older kindnet treated them as no-ops). Open the artifact
  # port cluster-wide so the operator — and any tenant namespace — can reach it.
  kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-artifact-fetch
  namespace: flux-system
spec:
  podSelector:
    matchLabels:
      app: source-controller
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - port: 9090
          protocol: TCP
EOF
}

# Installs JaaS from its released chart (latest). The webhook is off to avoid a
# cert-manager dependency; the bundled shared libraries are off because kind lacks
# the ImageVolume feature gate they mount through.
kurly::install_jaas() {
  echo "== install JaaS (helm) =="
  helm upgrade --install jaas oci://ghcr.io/metio/helm-charts/jaas \
    --namespace jaas-system --create-namespace \
    --set operator.enabled=true \
    --set operator.defaultServiceAccount=default \
    --set operator.webhook.enabled=false \
    --set libraries.grafonnet.enabled=false \
    --set libraries.docsonnet.enabled=false \
    --set libraries.xtd.enabled=false \
    --wait --timeout 5m
  kubectl -n jaas-system rollout status deploy \
    --selector app.kubernetes.io/name=jaas --timeout=300s || true
}

# Installs the stageset-controller from its released chart (latest).
kurly::install_stageset() {
  echo "== install stageset-controller (helm) =="
  helm upgrade --install stageset oci://ghcr.io/metio/helm-charts/stageset-controller \
    --namespace stageset-system --create-namespace \
    --wait --timeout 5m
}

# grant_tenant_publish_rbac <ns> [sa] — grant the tenant ServiceAccount (default
# "default") the RBAC the operator needs while impersonating it to publish: get /
# list / watch / create / update / patch / delete the snippet's ExternalArtifact
# and write its status. The operator acts AS the tenant SA (no `impersonate` verb
# on its own SA), so without this every reconcile fails RBACDenied at the publish
# step and the snippet never goes Ready.
kurly::grant_tenant_publish_rbac() {
  local ns=$1 sa=${2:-default}
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
rules:
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["externalartifacts", "externalartifacts/status"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # The operator impersonates the tenant SA to READ the JsonnetLibrary resources
  # the snippet references, so grant read access to them too. (Inline-only
  # snippets don't need this; ours references the kurly + k8s-libsonnet libs.)
  - apiGroups: ["jaas.metio.wtf"]
    resources: ["jsonnetlibraries"]
    verbs: ["get", "list", "watch"]
  # A source-backed JsonnetLibrary (ours: k8s-libsonnet from an OCIRepository)
  # makes the operator read that source CR for its artifact URL, so grant read on
  # the Flux source kinds (git/bucket too, so the helper generalizes).
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["ocirepositories", "gitrepositories", "buckets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { namespace: ${ns}, name: jaas-tenant-publish }
subjects:
  - { kind: ServiceAccount, name: ${sa}, namespace: ${ns} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: jaas-tenant-publish }
EOF
}
