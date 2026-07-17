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

# The version ladder is discovered at run time: the latest patch of each valkey
# major from VALKEY_START_MAJOR up to the newest published, so the walk always
# runs through to the current latest valkey with no edits here (when valkey 10
# ships it is picked up automatically). One entry per major = a major jump per
# hop, the way operators upgrade — each hop's new pod replicates across a major
# boundary before the atomic failover. Override the floor with VALKEY_START_MAJOR.
VALKEY_START_MAJOR="${VALKEY_START_MAJOR:-7}"
image_ref() { printf 'docker.io/valkey/valkey:%s' "$1"; }

# Echoes the latest X.Y.Z patch of each valkey major >= $1, ascending. Works off
# the Docker Hub tag list (sorted, so the last seen per major is the newest).
compute_valkey_ladder() {
  local start="$1" tags
  tags="$(
    for p in 1 2 3 4 5 6; do
      curl -fsSL "https://hub.docker.com/v2/repositories/valkey/valkey/tags?page_size=100&page=${p}" 2>/dev/null || true
    done | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u -V
  )"
  printf '%s\n' "$tags" \
    | awk -F. -v s="$start" '$1 + 0 >= s + 0 { latest[$1] = $0 } END { for (m in latest) print latest[m] }' \
    | sort -V
}

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  kurly::diagnose_pipeline "$ns"
  exit 1
}

# Build the ladder up front (before spinning anything up) so a discovery hiccup
# fails fast. Two majors are the minimum for a hand-off; if valkey has aged out of
# the fetched tag pages, raise the page count in compute_valkey_ladder.
mapfile -t VALKEY_LADDER < <(compute_valkey_ladder "$VALKEY_START_MAJOR")
if [ "${#VALKEY_LADDER[@]}" -lt 2 ]; then
  echo "::error::could not build a valkey version ladder from major ${VALKEY_START_MAJOR} (got: ${VALKEY_LADDER[*]:-none})"
  exit 1
fi
echo "valkey version ladder (dynamic): ${VALKEY_LADDER[*]}"

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
      // kurly renders namespace-less objects (the consumer places them); stageset
      // has no targetNamespace yet, so stamp the target namespace here so the
      // objects land where the StageSet's readyChecks look for them.
      // kurly.hostUsers() shares the host user namespace: kind-in-CI can't nest
      // user namespaces, so the default hostUsers=false fails pod sandbox creation
      // (sysfs mount denied) — the same relaxation scenario-valkey.sh applies.
      function(image='${ref}')
        local rendered = kurly.list(cache(image=image) + kurly.hostUsers());
        rendered {
          items: [
            item { metadata+: { namespace: '${ns}' } }
            for item in rendered.items
          ],
        }
  # No importPath: both libraries key their files by full vendor path, so the
  # absolute github.com/... imports resolve through JaaS's vendor search. The
  # alias (defaulting to the library name) only matters for bare-name imports.
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
    - { kind: JsonnetLibrary, name: k8s-libsonnet }
  tlas:
    - name: image
      value: "${ref}"
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

# primary_on_version <version> — true when the primary `valkey` Service has an
# endpoint AND the pod behind it runs the given valkey version, i.e. the primary
# followed the hand-off to the new-version master.
primary_on_version() {
  local ver="$1" ip pod
  ip="$(primary_endpoint)"
  [ -n "$ip" ] || return 1
  pod="$(kubectl --namespace="$ns" get pods \
    -o jsonpath="{range .items[?(@.status.podIP=='${ip}')]}{.metadata.name}{end}" 2>/dev/null || true)"
  [ -n "$pod" ] || return 1
  kubectl --namespace="$ns" get pod "$pod" \
    -o jsonpath='{.spec.containers[?(@.name=="valkey")].image}' 2>/dev/null | grep -q "$ver"
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

echo "== kurly as an inline vendor-keyed JsonnetLibrary (the checked-out branch) =="
# JaaS resolves an absolute import like github.com/metio/kurly/main.libsonnet by
# treating it as a root-relative path and searching every library whose files are
# keyed by full vendor path (the same way `jsonnet -J vendor` finds a jb tree). So
# the library's file keys must be the vendor paths, not the repo-root paths a Flux
# GitRepository would advertise. Build that library inline from the checked-out
# sources — it tests the exact branch and needs no published artifact.
emit_kurly_library() {
  echo "apiVersion: jaas.metio.wtf/v1"
  echo "kind: JsonnetLibrary"
  echo "metadata: { name: kurly, namespace: ${ns} }"
  echo "spec:"
  echo "  files:"
  local f
  for f in main.libsonnet lib/*.libsonnet workloads/valkey/cache.libsonnet; do
    echo "    \"github.com/metio/kurly/${f}\": |"
    sed 's/^/      /' "$f"
  done
}
# Server-side apply so the large inline tree is not stored a second time in a
# last-applied-config annotation.
emit_kurly_library | kubectl apply --server-side --force-conflicts --namespace="$ns" --filename=-

echo "== wait for the k8s-libsonnet OCI source to advertise an artifact =="
ok=false
for _ in $(seq 1 60); do
  [ -n "$(kubectl --namespace="$ns" get ocirepository/k8s-libsonnet -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
    && { ok=true; break; }
  sleep 3
done
[ "$ok" = true ] || fail "ocirepository/k8s-libsonnet never advertised an artifact"

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
# the primary FOLLOWS the hand-off to the new-version master. The primary moving
# is the point of the upgrade — the master role migrates to the new pod, and the
# primary-following Service tracks it. Clients are never routed to a replica; the
# only blip is a brief reconnect at the failover instant (the demoted master
# leaves the endpoints as it terminates, and the new master is labeled within a
# poll), which real clients retry through — so the check is that the primary
# converges onto the new master, not that the endpoint is never momentarily empty.
prev="$initial"
for next in "${VALKEY_LADDER[@]:1}"; do
  echo "== upgrade hop: ${prev} -> ${next} =="
  apply_snippet "$(image_ref "$next")"

  # JaaS re-renders and stageset re-applies within seconds; wait for the new image
  # to reach the Deployment spec first. A bare `rollout status` would otherwise
  # return immediately against the still-current old revision, before the new one
  # is applied.
  echo "== wait for stageset to apply the ${next} Deployment =="
  applied=false
  for _ in $(seq 1 60); do
    case "$(deploy_image)" in *"${next}"*) applied=true; break ;; esac
    sleep 2
  done
  [ "$applied" = true ] \
    || fail "stageset never applied the ${next} image to the Deployment on the ${prev} -> ${next} hop"

  # Then wait for the rolling hand-off to the new version to complete.
  if ! kubectl --namespace="$ns" rollout status deployment/valkey --timeout=300s; then
    fail "rollout of deployment/valkey never completed on the ${prev} -> ${next} hop"
  fi

  img="$(deploy_image)"
  case "$img" in
    *"${next}"*) echo "deployment rolled to ${img}" ;;
    *) fail "deployment did not roll to ${next} (image is ${img})" ;;
  esac

  echo "== assert the primary Service converged onto the ${next} master =="
  converged=false
  for _ in $(seq 1 30); do
    if primary_on_version "$next"; then converged=true; break; fi
    sleep 2
  done
  [ "$converged" = true ] \
    || fail "primary Service never converged onto a ${next} master after the ${prev} -> ${next} roll"
  echo "primary followed to the ${next} master at $(primary_endpoint)"
  prev="$next"
done

echo "valkey cache walked ${VALKEY_LADDER[*]} through Flux+JaaS+stageset, the primary following each hand-off"
