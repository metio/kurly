#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the cnpg workloads through the REAL production pipeline (Flux + JaaS +
# stageset-controller), proving the third thing neither other stageset scenario
# can: an INDIRECT roll driven by a custom resource a DIFFERENT operator owns.
#
# valkey proves zero-downtime rolls of kurly's own pods; tik proves versioned
# migrations. Both move a workload by changing the workload. This one changes
# something else entirely: a cnpg-image-catalog lists one PostgreSQL image per
# major, two clusters pin that major, and bumping the catalog's image rolls both
# clusters WITHOUT touching either Cluster CR.
#
# The whole story runs as one StageSet, on an EMPTY cluster:
#
#   operator (upstream Flux GitRepository)  ->  images (kurly)  ->  clusters (kurly)
#
# Three theses:
#
#   1. STAGE ORDERING — every arrow is a real dependency. The CRDs do not exist
#      until the operator stage applies them, so a stage that ran early or
#      concurrently would fail with "no matches for kind". The operator comes
#      from upstream's own release manifest: kurly authors intent, not other
#      people's release artifacts.
#   2. CONVERGENCE GATING — the clusters stage must open on the operator's
#      verdict, not on the apply returning. kstatus reads a freshly-applied
#      Cluster as Current (it knows the kstatus condition conventions; a Cluster
#      reports its own), so without the stage's CEL exprs the gate opens while
#      PostgreSQL is still bootstrapping, and a later stage in a real release
#      would start against a database that is not up. Asserted with no wait of
#      its own, so a gate that opens early fails here instead of being papered
#      over by a poll loop.
#   3. BLAST RADIUS   — one catalog line rolls EVERY cluster on that major, with
#      no Cluster CR touched. That is the feature and the risk, so both clusters
#      must land on the new image, and both CRs must keep the generation they
#      started with — a moved generation would mean something rewrote the
#      Cluster and the roll did not come from the catalog at all.
#
# Note what the bump does NOT test: a catalog change touches no Cluster CR, so
# stageset never re-evaluates the clusters stage across it. The convergence gate
# above is proved on the initial install, where the stage genuinely has
# something to wait for.
#
# Deliberately NO migrations: a catalog bump never moves
# app.kubernetes.io/version, so it crosses no migration boundary by design (the
# workload label stamps kurly, not the resolved PostgreSQL image). That
# decoupling is exactly why tik owns the migration scenario and this one does
# not.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-cnpg-stageset

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.30.0"

# The bump the walk performs. Two patches of the same major: same major keeps
# this an image roll rather than a (slow, failure-prone) major upgrade, which is
# what the catalog pattern is actually for.
PG_MAJOR="17"
PG_FROM="ghcr.io/cloudnative-pg/postgresql:17.2"
PG_TO="ghcr.io/cloudnative-pg/postgresql:17.4"

# Two clusters on the one catalog: one is not enough to show a blast radius.
CLUSTERS=(orders-db billing-db)

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  kurly::diagnose_pipeline "$ns"
  echo "::group::cnpg state"
  # The ladder's own account of itself: which stage is stuck, and what it says.
  kubectl --namespace="$ns" get stageset postgres \
    -o jsonpath='{range .status.stages[*]}{.name}{" -> "}{.phase}{" | "}{.message}{"\n"}{end}' 2>/dev/null || true
  # The operator arrives as stage 1, so its source and its CRDs are part of the
  # failure surface: a stalled GitRepository or an unestablished CRD stops the
  # ladder before any kurly stage runs.
  kubectl --namespace="$ns" get gitrepository/cnpg-operator -o yaml 2>/dev/null | tail -25 || true
  kubectl get crd 2>/dev/null | grep -i cnpg || echo "(no cnpg CRDs — the operator stage never applied)"
  kubectl --namespace="$ns" get imagecatalog,cluster -o wide 2>/dev/null || true
  kubectl --namespace="$ns" get imagecatalog postgres -o yaml 2>/dev/null | tail -20 || true
  local c
  for c in "${CLUSTERS[@]}"; do
    kubectl --namespace="$ns" get cluster "$c" -o yaml 2>/dev/null | tail -40 || true
  done
  kubectl --namespace=cnpg-system logs --selector=app.kubernetes.io/name=cloudnative-pg \
    --tail=80 --prefix 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

# apply_catalog <image> — (re)renders the image catalog with one image for
# PG_MAJOR. This is the ONLY thing the walk ever changes.
apply_catalog() {
  local image="$1"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: cnpg-catalog
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local catalog = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet';
      function(image='${image}')
        local rendered = kurly.list(catalog(name='postgres', images={ '${PG_MAJOR}': image }));
        rendered {
          items: [
            item { metadata+: { namespace: '${ns}' } }
            for item in rendered.items
          ],
        }
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-image-catalog }
    - { kind: JsonnetLibrary, name: k8s-libsonnet }
  tlas:
    - name: image
      value: "${image}"
EOF
}

# apply_clusters — renders both clusters, each pinning PG_MAJOR from the
# catalog. Applied once and never re-rendered: the whole point is that the roll
# happens with these CRs untouched.
#
# Single-instance, tiny volumes: kind has one node, and this scenario is about
# the catalog interaction, not CNPG's own failover (scenario-cnpg.sh covers the
# CR reconciling at all).
apply_clusters() {
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: cnpg-clusters
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
      local one(name) = cluster(
        name=name,
        instances=1,
        storageSize='256Mi',
        catalog='postgres',
        major=${PG_MAJOR},
        // A PodMonitor needs the Prometheus Operator CRDs, which this throwaway
        // cluster does not install.
        enablePodMonitor=false,
      );
      local rendered = kurly.listOf([
        one('${CLUSTERS[0]}').cluster,
        one('${CLUSTERS[1]}').cluster,
      ]);
      rendered {
        items: [
          item { metadata+: { namespace: '${ns}' } }
          for item in rendered.items
        ],
      }
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-cluster }
    - { kind: JsonnetLibrary, name: k8s-libsonnet }
EOF
}

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

ready_status() {
  kubectl --namespace="$ns" get "$1" "$2" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true
}

# The phase and message stageset reports for ONE stage. Waiting on the StageSet
# as a whole only ever reports that something, somewhere, is not Ready; the
# ladder has three stages with very different failure modes, so each is waited
# on by name.
stage_phase() {
  kubectl --namespace="$ns" get stageset postgres \
    -o jsonpath="{range .status.stages[?(@.name=='$1')]}{.phase}{end}" 2>/dev/null || true
}
stage_message() {
  kubectl --namespace="$ns" get stageset postgres \
    -o jsonpath="{range .status.stages[?(@.name=='$1')]}{.message}{end}" 2>/dev/null || true
}

# await_stage <name> <polls> — block until a stage is Ready, naming the stage
# and its own message on failure instead of timing out anonymously.
await_stage() {
  local name="$1" polls="$2" i
  for i in $(seq 1 "$polls"); do
    case "$(stage_phase "$name")" in
      Ready) echo "stage ${name}: Ready after ${i} polls"; return 0 ;;
      Failed) fail "stage ${name} failed: $(stage_message "$name")" ;;
    esac
    sleep 5
  done
  fail "stage ${name} never became Ready (phase: '$(stage_phase "$name")', message: '$(stage_message "$name")')"
}

wait_ready() {
  local kind="$1" name="$2" polls="${3:-60}" i
  for i in $(seq 1 "$polls"); do
    [ "$(ready_status "$kind" "$name")" = "True" ] && { echo "${kind}/${name} Ready=True after ${i} polls"; return 0; }
    sleep 5
  done
  fail "${kind}/${name} never reached Ready=True"
}

# The image CNPG resolved for a cluster — the catalog's answer, not a CR field.
cluster_image() {
  kubectl --namespace="$ns" get cluster "$1" \
    -o jsonpath='{.status.image}' 2>/dev/null || true
}

# The generation of a Cluster CR. The blast-radius proof needs this to NOT move
# across the bump: a changed generation would mean the CR itself was rewritten,
# and the roll would prove nothing about catalog-driven upgrades.
cluster_generation() {
  kubectl --namespace="$ns" get cluster "$1" \
    -o jsonpath='{.metadata.generation}' 2>/dev/null || true
}

cluster_healthy() {
  case "$(kubectl --namespace="$ns" get cluster "$1" -o jsonpath='{.status.phase}' 2>/dev/null || true)" in
    *healthy*) return 0 ;;
    *) return 1 ;;
  esac
}

# await_all_healthy <polls> — every cluster reports a healthy phase.
await_all_healthy() {
  local polls="$1" c i ok
  for i in $(seq 1 "$polls"); do
    ok=true
    for c in "${CLUSTERS[@]}"; do
      cluster_healthy "$c" || ok=false
    done
    [ "$ok" = true ] && return 0
    sleep 5
  done
  return 1
}

# await_all_on_image <image> <polls> — every cluster resolved to the image.
await_all_on_image() {
  local want="$1" polls="$2" c i ok
  for i in $(seq 1 "$polls"); do
    ok=true
    for c in "${CLUSTERS[@]}"; do
      [ "$(cluster_image "$c")" = "$want" ] || ok=false
    done
    [ "$ok" = true ] && return 0
    sleep 5
  done
  return 1
}

# ---------------------------------------------------------------------------
# Pipeline
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
metadata: { name: kurly-cnpg-stageset-deployer }
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

echo "== kurly + workloads through the OCIRepository path (branch-built images) =="
# The prime consumption path: build THIS branch's library and both cnpg workload
# images, push them to the in-cluster registry, and let Flux pull them as
# OCIRepositories — so the image packaging is proven here, not only at release.
# Each snippet imports only its own workload (the catalog snippet the image
# catalog, the cluster snippet the cluster), so each references just that one.
kurly::install_registry
kurly::publish_images cnpg-cluster cnpg-image-catalog
kurly::emit_oci_library "$ns" kurly kurly
kurly::emit_oci_library "$ns" kurly-cnpg-cluster kurly-cnpg-cluster
kurly::emit_oci_library "$ns" kurly-cnpg-image-catalog kurly-cnpg-image-catalog

echo "== wait for every OCI source to advertise an artifact =="
kurly::wait_ocirepository "$ns" k8s-libsonnet
kurly::wait_ocirepository "$ns" kurly
kurly::wait_ocirepository "$ns" kurly-cnpg-cluster
kurly::wait_ocirepository "$ns" kurly-cnpg-image-catalog

# ---------------------------------------------------------------------------
# Phase 1 — install: catalog first, then the clusters that pin it
# ---------------------------------------------------------------------------

echo "== phase 1: install the catalog at ${PG_FROM} and two clusters pinning major ${PG_MAJOR} =="
apply_catalog "$PG_FROM"
apply_clusters
wait_ready jsonnetsnippet cnpg-catalog 90
wait_ready jsonnetsnippet cnpg-clusters 90

# The CloudNativePG operator, from UPSTREAM's own release manifest — kurly does
# not author it. That manifest is ~21k lines, all but a thousand of them the 11
# CRDs, and it is CNPG's release artifact rather than anyone's intent to model:
# re-authoring it in Jsonnet would be a fork that has to be re-vendored every
# release. Flux consumes it in place, tagged and immutable, and kurly's stages
# ride behind it.
#
# `ignore` prunes the artifact to the one manifest so the stage applies that file
# and nothing else — releases/ also holds older manifests and a .go file, all of
# which the stage would otherwise apply.
#
# The four lines are gitignore semantics, not redundancy: a file cannot be
# re-included once its parent directory is excluded, so `/*` + the `!` for the
# file alone would exclude releases/ wholesale and publish an EMPTY artifact.
# The directory has to be re-included, then its contents excluded, then the one
# file re-included.
echo "== the CNPG operator ${CNPG_VERSION} as an upstream Flux source =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: cnpg-operator, namespace: ${ns} }
spec:
  interval: 12h
  url: https://github.com/cloudnative-pg/cloudnative-pg
  ref: { tag: v${CNPG_VERSION} }
  ignore: |
    /*
    !/releases/
    /releases/*
    !/releases/cnpg-${CNPG_VERSION}.yaml
EOF

echo "== wait for the operator GitRepository to advertise an artifact =="
ok=false
for _ in $(seq 1 60); do
  [ -n "$(kubectl --namespace="$ns" get gitrepository/cnpg-operator -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
    && { ok=true; break; }
  sleep 5
done
[ "$ok" = true ] || fail "gitrepository/cnpg-operator never advertised an artifact"

# An artifact is published whether or not it contains anything, so its existence
# proves nothing about the ignore rules above. Flux reports the archive size —
# an empty tree would sail past the check above and only surface 5 minutes later
# as the operator stage's readyChecks timing out on CRDs that never arrive.
size="$(kubectl --namespace="$ns" get gitrepository/cnpg-operator -o jsonpath='{.status.artifact.size}' 2>/dev/null || true)"
echo "operator artifact size: ${size:-unknown} bytes"
if [ -z "$size" ] || [ "$size" -lt 10000 ]; then
  fail "the operator artifact is empty or tiny (${size:-unknown} bytes) — the ignore rules pruned away the manifest"
fi

# The three-stage ordering, and the reason this scenario is worth its runtime:
# every arrow below is a REAL dependency, not a preference.
#
#   operator -> images:   the catalog is a postgresql.cnpg.io CR, so its CRD must
#                         be Established before the manifest can even be applied.
#   images   -> clusters: a cluster cannot resolve an image for a major the
#                         catalog does not list yet.
#
# Nothing here pre-creates the CRDs — the cluster starts empty. So if stageset
# ran these stages concurrently, or advanced before the operator's CRDs were
# Established, the images stage would fail outright with "no matches for kind".
# A green StageSet IS the ordering proof; it cannot pass by luck.
#
# No stage lists readyChecks.checks, because none needs to: stageset's kstatus
# wait already covers every object a stage applied. The operator stage applies
# the CRDs and the controller Deployment, so it is gated on them — an explicit
# check would only restate what the stage already waits for, and would have to be
# kept in step with a 21k-line upstream manifest to stay true. checks are for
# gating on something a stage did NOT apply; only `timeout` is set here.
#
# The clusters stage is the exception that shows the rule: what it waits for
# (CNPG converging a Cluster) is not something kstatus can infer, so that gate is
# spelled out in CEL below.
echo "== StageSet: operator (upstream) -> images (kurly) -> clusters (kurly) =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: postgres, namespace: ${ns} }
spec:
  interval: 1m
  serviceAccountName: stageset-deployer
  stages:
    - name: operator
      sourceRef: { kind: GitRepository, name: cnpg-operator }
      path: ./releases
      readyChecks:
        # The operator image is a few hundred MB and 11 CRDs must establish, on a
        # kind node with a cold image cache.
        timeout: 10m
    - name: images
      sourceRef: { name: cnpg-catalog }
      readyChecks:
        timeout: 5m
    - name: clusters
      sourceRef: { name: cnpg-clusters }
      readyChecks:
        # Two PostgreSQL instances bootstrap from scratch behind this gate.
        timeout: 10m
        # kstatus cannot know when a CNPG Cluster has converged. It understands
        # the kstatus condition conventions, and a Cluster reports its own, so a
        # freshly-applied Cluster reads as Current and the stage goes Ready
        # seconds after the CRs land — while PostgreSQL is still bootstrapping.
        # Expressing the gate in CEL is what exprs are for: the stage now waits
        # for the operator's verdict rather than for the apply to return.
        exprs:
          - apiVersion: postgresql.cnpg.io/v1
            kind: Cluster
            current: "has(status.conditions) && status.conditions.exists(c, c.type == 'Ready' && c.status == 'True')"
EOF

# Walk the ladder rung by rung. The stages have wildly different budgets — the
# operator pulls a large image and establishes 11 CRDs, the clusters bootstrap
# two PostgreSQL instances from scratch — and a single wait on the StageSet
# would collapse all three into one anonymous timeout.
echo "== wait for the ladder: operator -> images -> clusters =="
await_stage operator 150
await_stage images 60
await_stage clusters 180

# The gate is only worth having if it means what it says. Check convergence with
# NO wait of its own, the instant the stage reports Ready: if the clusters are
# not healthy right now, the stage opened on "the CRs applied" rather than "the
# operator converged", and every later stage in a real release would start
# against a PostgreSQL that is not up. Polling here instead would hide exactly
# that — the scenario would go green either way.
echo "== assert: the clusters stage opened only after CNPG converged =="
for c in "${CLUSTERS[@]}"; do
  cluster_healthy "$c" \
    || fail "stage clusters went Ready while ${c} reports '$(kubectl --namespace="$ns" get cluster "$c" -o jsonpath='{.status.phase}' 2>/dev/null)' — the gate did not wait for the operator"
done
echo "both clusters were healthy the moment the stage opened"

wait_ready stageset postgres 60

echo "== assert: stageset installed the operator (nothing else did) =="
kubectl --namespace=cnpg-system rollout status deployment/cnpg-controller-manager --timeout=60s \
  || fail "the operator stage went Ready without a running controller-manager"

echo "== wait for both clusters to come up healthy on ${PG_FROM} =="
await_all_healthy 120 || fail "the clusters never became healthy on the initial ${PG_FROM}"
await_all_on_image "$PG_FROM" 60 \
  || fail "the clusters did not resolve ${PG_FROM} from the catalog (got: $(cluster_image "${CLUSTERS[0]}") / $(cluster_image "${CLUSTERS[1]}"))"

# Record what the CRs look like before the bump — the untouched-CR proof.
declare -A GEN_BEFORE
for c in "${CLUSTERS[@]}"; do
  GEN_BEFORE["$c"]="$(cluster_generation "$c")"
  echo "${c}: image=$(cluster_image "$c") generation=${GEN_BEFORE[$c]}"
done

# ---------------------------------------------------------------------------
# Phase 2 — the indirect roll: bump ONLY the catalog
# ---------------------------------------------------------------------------

echo "== phase 2: bump the catalog ${PG_FROM} -> ${PG_TO} (no Cluster CR is touched) =="
apply_catalog "$PG_TO"

echo "== assert: the catalog itself carries the new image =="
bumped=false
for _ in $(seq 1 60); do
  [ "$(kubectl --namespace="$ns" get imagecatalog postgres \
    -o jsonpath="{.spec.images[?(@.major==${PG_MAJOR})].image}" 2>/dev/null || true)" = "$PG_TO" ] \
    && { bumped=true; break; }
  sleep 3
done
[ "$bumped" = true ] || fail "stageset never applied the ${PG_TO} image to the catalog"

echo "== assert: BOTH clusters roll onto ${PG_TO} (the blast radius) =="
await_all_on_image "$PG_TO" 120 \
  || fail "not every cluster followed the catalog to ${PG_TO} (got: $(cluster_image "${CLUSTERS[0]}") / $(cluster_image "${CLUSTERS[1]}"))"
for c in "${CLUSTERS[@]}"; do
  echo "${c} followed the catalog to $(cluster_image "$c")"
done

echo "== assert: both clusters converge back to healthy =="
await_all_healthy 120 || fail "the clusters never returned to healthy after the catalog bump"

# The heart of the scenario: the clusters rolled, and their CRs never moved. A
# changed generation would mean something rewrote the Cluster — and the upgrade
# would have come from the CR, not the catalog.
echo "== assert: the Cluster CRs were never touched =="
for c in "${CLUSTERS[@]}"; do
  now="$(cluster_generation "$c")"
  [ "$now" = "${GEN_BEFORE[$c]}" ] \
    || fail "${c}'s CR was rewritten across the bump (generation ${GEN_BEFORE[$c]} -> ${now}) — the roll did not come from the catalog"
done
echo "both Cluster CRs unchanged (generation ${GEN_BEFORE[${CLUSTERS[0]}]}) — the roll came from the catalog alone"

echo "== assert: the StageSet is Ready with both clusters converged =="
wait_ready stageset postgres 60

echo "cnpg: one catalog line rolled ${#CLUSTERS[@]} clusters from ${PG_FROM} to ${PG_TO} through Flux+JaaS+stageset, with no Cluster CR touched"
