#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the valkey cache through the REAL production pipeline: Flux (source-
# controller + ExternalArtifact) + JaaS (renders the workload from a JsonnetSnippet)
# + stageset-controller (applies and rolls the rendered manifests). The raw-apply
# complement lives in scenario-valkey.sh; this one proves the same zero-downtime
# hand-off survives a multi-hop version walk driven end to end by the operators.
#
# The scenario deploys the cache at the first tag of a version ladder, then walks
# the ladder one major/minor step at a time by patching only the JsonnetSnippet's
# image — JaaS re-renders, publishes a new ExternalArtifact revision, and the
# StageSet rolls it (maxSurge=1/maxUnavailable=0 from the cache workload). Across
# every hop the primary `valkey` Service must never lose its endpoint: that
# continuity is the zero-downtime proof. There are deliberately NO migrations —
# the cache is ephemeral (the dataset moves by replication, not a volume), so a
# migration would be contrived; the point is many upgrades, zero downtime, none.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-valkey-stageset
branch="${KURLY_GIT_BRANCH:-main}"

# The version ladder: latest patch of each line, ONE major/minor step at a time
# (operators don't skip majors). The cross-major 7.2->8.0 hop exercises cross-
# version replication in the hand-off. Kept as an easy-to-edit array so a hop can
# be trimmed if a cross-major replication incompatibility ever surfaces. These
# versions are intentionally pinned — the lower rungs must not float — so a
# packageRule in renovate.json disables all updates for this file.
VALKEY_LADDER=(7.2.13 8.0.9 8.1.8)
image_ref() { printf 'docker.io/valkey/valkey:%s' "$1"; }

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  kurly::diagnose_pipeline "$ns"
  exit 1
}

# Applies (creates or updates) the JsonnetSnippet rendering the cache at $1. Both
# the main.jsonnet default and the tlas.image drive the render depending on how
# JaaS invokes the function, so set BOTH to the target ref to be safe.
apply_snippet() {
  local ref="$1"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: valkey
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cache = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';
      function(image='${ref}')
        kurly.list(cache(image=image))
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: k8s-libsonnet, importPath: github.com/jsonnet-libs/k8s-libsonnet }
  tlas:
    image: ["${ref}"]
EOF
}

# Echoes the Ready condition status of a namespaced object (or "").
ready_status() {
  kubectl --namespace="$ns" get "$1" "$2" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true
}

# Blocks until <kind>/<name> reports Ready=True; on timeout dumps the pipeline.
wait_ready() {
  local kind="$1" name="$2" polls="${3:-60}" i
  for i in $(seq 1 "$polls"); do
    [ "$(ready_status "$kind" "$name")" = "True" ] && { echo "${kind}/${name} Ready=True after ${i} polls"; return 0; }
    sleep 5
  done
  fail "${kind}/${name} never reached Ready=True"
}

# Echoes the first endpoint address of the primary `valkey` Service (or "").
primary_endpoint() {
  kubectl --namespace="$ns" get endpoints valkey \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true
}

# Echoes the deployment's valkey-container image.
deploy_image() {
  kubectl --namespace="$ns" get deploy valkey \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="valkey")].image}' 2>/dev/null || true
}

# ---------------------------------------------------------------------------

kurly::install_flux
kurly::install_jaas
kurly::install_stageset

kurly::namespace "$ns"
kurly::grant_tenant_publish_rbac "$ns" default

echo "== deployer ServiceAccount for the StageSet (cluster-admin, e2e simplicity) =="
kubectl apply --filename=- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata: { name: stageset-deployer, namespace: ${ns} }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: kurly-valkey-stageset-deployer }
subjects:
  - { kind: ServiceAccount, name: stageset-deployer, namespace: ${ns} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin }
EOF

echo "== k8s-libsonnet from the JOI OCI image (the production dependency path) =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec:
  interval: 1h
  url: oci://ghcr.io/metio/joi-jsonnet-libs-k8s-libsonnet
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: k8s-libsonnet, namespace: ${ns} }
spec:
  sourceRef: { kind: OCIRepository, name: k8s-libsonnet }
EOF

echo "== kurly from a Flux GitRepository at the branch under test (${branch}) =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: kurly, namespace: ${ns} }
spec:
  interval: 1h
  url: https://github.com/metio/kurly
  ref: { branch: ${branch} }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ${ns} }
spec:
  sourceRef: { kind: GitRepository, name: kurly }
EOF

echo "== wait for the Flux sources to advertise an artifact =="
for kind in ocirepository/k8s-libsonnet gitrepository/kurly; do
  ok=false
  for _ in $(seq 1 60); do
    [ -n "$(kubectl --namespace="$ns" get "$kind" -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
      && { ok=true; break; }
    sleep 3
  done
  [ "$ok" = true ] || fail "${kind} never advertised an artifact"
done

initial="${VALKEY_LADDER[0]}"
echo "== initial deploy: render the cache at $(image_ref "$initial") =="
apply_snippet "$(image_ref "$initial")"

echo "== wait for JaaS to publish the snippet's ExternalArtifact (Ready=True) =="
wait_ready jsonnetsnippet valkey 90

echo "== StageSet deploys the snippet's ExternalArtifact =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: valkey, namespace: ${ns} }
spec:
  interval: 1m
  serviceAccountName: stageset-deployer
  stages:
    - name: cache
      sourceRef: { name: valkey }
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: valkey, namespace: ${ns} }
EOF

wait_ready stageset valkey 90
if ! kubectl --namespace="$ns" rollout status deployment/valkey --timeout=300s; then
  fail "initial rollout of deployment/valkey never completed"
fi

echo "== wait for the primary Service to gain an endpoint (labeler promoted the master) =="
addr=""
for _ in $(seq 1 40); do
  addr="$(primary_endpoint)"
  [ -n "$addr" ] && break
  sleep 3
done
[ -n "$addr" ] || fail "the primary-following Service never gained an endpoint"
echo "primary endpoint: ${addr}"

# The multi-hop version walk: for each remaining tag, patch the snippet and prove
# the primary Service keeps an endpoint through the entire roll.
prev="$initial"
for next in "${VALKEY_LADDER[@]:1}"; do
  echo "== upgrade hop: ${prev} -> ${next} =="
  apply_snippet "$(image_ref "$next")"

  # Poll the endpoint continuously across the roll; it must NEVER be empty. JaaS
  # re-renders on the snippet change and the StageSet re-applies within seconds,
  # so start watching immediately after the patch.
  echo "== assert the primary Service never loses its endpoint across the roll =="
  for _ in $(seq 1 60); do
    [ -n "$(primary_endpoint)" ] || fail "zero-downtime BROKEN: primary Service lost its endpoint during the ${prev} -> ${next} roll"
    sleep 2
  done

  if ! kubectl --namespace="$ns" rollout status deployment/valkey --timeout=300s; then
    fail "rollout of deployment/valkey never completed on the ${prev} -> ${next} hop"
  fi

  img="$(deploy_image)"
  case "$img" in
    *"${next}"*) echo "deployment rolled to ${img}" ;;
    *) fail "deployment did not roll to ${next} (image is ${img})" ;;
  esac

  [ -n "$(primary_endpoint)" ] || fail "primary Service has no endpoint after settling on ${next}"
  prev="$next"
done

echo "valkey cache walked ${VALKEY_LADDER[*]} through Flux+JaaS+stageset with zero downtime"
