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
  # Did the applied workload objects land ANYWHERE? (A kind:List that the applier
  # never expands, or objects placed in another namespace, both read as NotFound
  # to the readyChecks.) And what did stageset record as applied?
  echo "--- valkey workload objects across all namespaces ---"
  kubectl get deployments,statefulsets,services,pods --all-namespaces 2>/dev/null \
    | grep -i valkey || echo "(no valkey workload objects found in any namespace)"
  echo "--- StageInventory (what stageset applied) ---"
  kubectl --namespace="$ns" get stageinventory -o yaml 2>/dev/null | grep -iE "kind:|name:|namespace:|apiVersion:" | head -40 || true
  # The controllers' own pods and logs — where a hang that never writes a CR
  # condition (an OOMKill, a crash, a stuck fetch) actually shows up.
  echo "--- JaaS operator (pods + logs) ---"
  kubectl --namespace=jaas-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=jaas-system logs --selector=app.kubernetes.io/instance=jaas \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
  echo "--- stageset-controller (pods + logs) ---"
  kubectl --namespace=stageset-system get pods -o wide 2>/dev/null || true
  kubectl --namespace=stageset-system logs --selector=app.kubernetes.io/instance=stageset \
    --all-containers=true --tail=80 --prefix 2>/dev/null || true
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
  # The chart's default 64Mi is far too small to render k8s-libsonnet (go-jsonnet
  # peaks at hundreds of MB), so the operator OOMKills on the first reconcile —
  # give it room.
  helm upgrade --install jaas oci://ghcr.io/metio/helm-charts/jaas \
    --namespace jaas-system --create-namespace \
    --set operator.enabled=true \
    --set operator.defaultServiceAccount=default \
    --set operator.webhook.enabled=false \
    --set libraries.grafonnet.enabled=false \
    --set libraries.docsonnet.enabled=false \
    --set libraries.xtd.enabled=false \
    --set resources.memory=2Gi \
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

# The in-cluster registry that serves the branch-built images to Flux. The
# stageset scenarios consume kurly through the SAME path a real deployment does —
# an OCIRepository — instead of an inline JsonnetLibrary, so the image packaging
# (the Containerfiles, the single layer, the vendor-tree layout) is exercised on
# every run, not just at release. Building from the checkout keeps the "tests the
# exact branch" property the inline library had.
#
# One registry, reached two ways: the host pushes over a NodePort the e2e
# workflow maps to localhost:5001 (registry:true), and source-controller pulls
# over the ClusterIP by DNS. Plain HTTP, so the host push relies on Docker
# trusting localhost and the OCIRepository sets `insecure: true`.
KURLY_REGISTRY_PUSH="localhost:5001"
KURLY_REGISTRY_PULL="registry.registry.svc.cluster.local:5000"
KURLY_IMAGE_TAG="e2e"

# Deploys registry:2 in its own namespace with a fixed NodePort, and waits for it
# to serve. The NodePort (30500) is the one the workflow's kind config maps to the
# host, so a scenario that calls this MUST run under a `registry: true` e2e job.
kurly::install_registry() {
  echo "== install in-cluster registry =="
  kubectl apply --filename=- <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: registry }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: registry, namespace: registry }
spec:
  replicas: 1
  selector: { matchLabels: { app: registry } }
  template:
    metadata: { labels: { app: registry } }
    spec:
      containers:
        - name: registry
          image: docker.io/library/registry:2
          ports:
            - { containerPort: 5000 }
---
apiVersion: v1
kind: Service
metadata: { name: registry, namespace: registry }
spec:
  type: NodePort
  selector: { app: registry }
  ports:
    - { port: 5000, targetPort: 5000, nodePort: 30500, protocol: TCP }
EOF
  kubectl -n registry rollout status deploy/registry --timeout=180s
}

# Builds the branch's library and workload images and pushes them to the registry
# through the host port-map. Usage: kurly::publish_images <workload>...
# The library is always published (every stage imports it); each named workload's
# source image is published too. Push is retried, since the NodePort route can lag
# the pod becoming Ready.
kurly::publish_images() {
  local push
  _push() {
    local ref="$1" i
    for i in $(seq 1 12); do
      docker push "$ref" && return 0
      echo "push $ref failed (attempt $i) — retrying"
      sleep 5
    done
    echo "push $ref never succeeded" >&2
    return 1
  }
  echo "== build and push the kurly library image =="
  push="${KURLY_REGISTRY_PUSH}/kurly:${KURLY_IMAGE_TAG}"
  docker build --file Containerfile --tag "$push" .
  _push "$push"
  local wl
  for wl in "$@"; do
    echo "== build and push the ${wl} workload image =="
    push="${KURLY_REGISTRY_PUSH}/kurly-${wl}:${KURLY_IMAGE_TAG}"
    docker build --file workload.Containerfile --build-arg "WORKLOAD=${wl}" --tag "$push" .
    _push "$push"
  done
}

# Emits an OCIRepository (pulling from the in-cluster registry, insecure HTTP) and
# the JsonnetLibrary that sources it. Usage:
#   kurly::emit_oci_library <ns> <library-name> <image-repo>
# e.g. `kurly::emit_oci_library cache kurly kurly` and
#      `kurly::emit_oci_library cache kurly-valkey kurly-valkey`.
kurly::emit_oci_library() {
  local ns="$1" name="$2" repo="$3"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: ${name}, namespace: ${ns} }
spec:
  interval: 1h
  insecure: true
  url: oci://${KURLY_REGISTRY_PULL}/${repo}
  ref: { tag: ${KURLY_IMAGE_TAG} }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: ${name}, namespace: ${ns} }
spec:
  sourceRef: { kind: OCIRepository, name: ${name} }
EOF
}

# Blocks until an OCIRepository advertises a fetched artifact (or fails loudly).
kurly::wait_ocirepository() {
  local ns="$1" name="$2" i
  for i in $(seq 1 60); do
    [ -n "$(kubectl --namespace="$ns" get ocirepository/"$name" -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
      && { echo "ocirepository/${name} has an artifact"; return 0; }
    sleep 3
  done
  echo "ocirepository/${name} never advertised an artifact" >&2
  return 1
}
