#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the tik workload through the REAL production pipeline (Flux + JaaS +
# stageset-controller), proving the half of the stageset contract the valkey
# scenario deliberately cannot: VERSIONED MIGRATIONS. valkey is an ephemeral
# cache with no migrations, so its walk proves zero-downtime rolls and nothing
# about action ladders. tik is the opposite workload — a single writer over a
# ReadWriteOnce store, recreated rather than rolled, carrying a migration ladder
# — so this scenario asserts the gating instead of the continuity.
#
# Four theses, one per phase, walking a three-tag ladder (the classic
# current-2 -> current-1 -> current):
#
#   1. BASELINE   — the first install records status.version and runs NO
#                   migrations (the deployment already IS that version).
#   2. CROSSING   — a hop across a migration's `to` boundary runs its job, and
#                   the job is recorded in status.executedMigrations.
#   3. IDEMPOTENCY— a re-render that does not move the version does not re-run
#                   an already-executed migration.
#   4. BLOCKING   — a migration whose job FAILS halts its anchoring stage as
#                   MigrationDirty: the Deployment must NOT advance to the new
#                   image. The halt is deliberate and does not clear itself —
#                   repairing the job is necessary but not sufficient, so the
#                   phase walks the documented recovery (republish, then ask for
#                   a reconcile). This is the failure path nothing else in the
#                   repo covers, and the reason to have this file.
#
# stageset reads the deployed version from an object's
# metadata.labels['app.kubernetes.io/version'] (spec.version.fromObject), which
# is exactly what kurly.version() stamps — so the ladder is driven by the
# workload version, NOT the image tag. The scenario keeps the two in lockstep
# (each hop composes `+ kurly.version(<tag>)`) so a human reading the log sees
# one number move.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-tik-stageset

# The ladder is discovered at run time from the published tik tags, so the walk
# always ends at the current release with no edits here. tik's calver
# (2026.7.14173105) parses as semver — major.minor.patch — which is what
# stageset's `to` boundary and `from` constraint require.
TIK_IMAGE="${TIK_IMAGE:-ghcr.io/metio/tik}"
image_ref() { printf '%s:%s' "$TIK_IMAGE" "$1"; }

# The stand-in image the migration jobs run. Needs nothing but a shell to exit
# with a chosen code.
# renovate: datasource=docker depName=busybox
MIGRATION_JOB_IMAGE="docker.io/library/busybox:1.37.0"

# Echoes the newest three calver tags of the tik image, ascending. Anonymous
# pull tokens are enough for a public GHCR repository.
compute_tik_ladder() {
  local token
  token="$(curl -fsSL "https://ghcr.io/token?scope=repository:metio/tik:pull&service=ghcr.io" | jq -r .token)"
  curl -fsSL -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/metio/tik/tags/list" \
    | jq -r '.tags[]' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -u -V \
    | tail -3
}

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  kurly::diagnose_pipeline "$ns"
  echo "::group::migration state"
  kubectl --namespace="$ns" get stageset tik -o jsonpath='{.status}' 2>/dev/null || true
  echo
  kubectl --namespace="$ns" get jobs -o wide 2>/dev/null || true
  kubectl --namespace="$ns" logs --selector=job-name --all-containers=true --tail=60 --prefix 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

# Three tags are the minimum: one to baseline on, one to cross a boundary with,
# one to prove the blocking path. Fail fast rather than half-running the walk.
mapfile -t TIK_LADDER < <(compute_tik_ladder)
if [ "${#TIK_LADDER[@]}" -lt 3 ]; then
  fail "could not build a three-tag tik ladder (got: ${TIK_LADDER[*]:-none})"
fi
V1="${TIK_LADDER[0]}"
V2="${TIK_LADDER[1]}"
V3="${TIK_LADDER[2]}"
echo "tik version ladder (dynamic): ${V1} -> ${V2} -> ${V3}"

# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------

# apply_snippet <version> — (re)renders the tik backend at a version. The image
# tag and the app.kubernetes.io/version label are moved together: the label is
# what stageset gates migrations on, the image is what actually runs.
#
# kurly renders namespace-less objects (the consumer places them) and stageset
# has no targetNamespace, so the namespace is stamped here — same as the valkey
# scenario. kurly.hostUsers() shares the host user namespace because kind-in-CI
# cannot nest one; every other hardening knob stays on.
apply_snippet() {
  local ver="$1"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: tik
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backend = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';
      function(image='$(image_ref "$ver")', version='${ver}')
        local rendered = kurly.list(
          backend(image=image)
          + kurly.version(version)
          + kurly.hostUsers()
          // kind's default StorageClass is WaitForFirstConsumer; a small claim
          // keeps the throwaway cluster honest without slowing the walk.
          + kurly.store('/var/lib/tik', '128Mi')
        );
        rendered {
          items: [
            item { metadata+: { namespace: '${ns}' } }
            for item in rendered.items
          ],
        }
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
    - { kind: JsonnetLibrary, name: k8s-libsonnet }
  tlas:
    image: ["$(image_ref "$ver")"]
    version: ["${ver}"]
EOF
}

# apply_migration_job <name> <exit-code> — publishes a Job manifest as its own
# ExternalArtifact for a migration action to reference. Exit code 0 stands in
# for a real `tik reprocess` / `tik verify`; a non-zero code is how the BLOCKING
# phase forces a migration failure without waiting for a genuinely broken store.
#
# The job runs busybox rather than the tik image for two reasons: the tik image
# is distroless and has no shell to script an exit code with, and a real
# `tik verify` would have to mount the store — which is ReadWriteOnce and held
# by the running backend pod, so the job would deadlock on the volume. What is
# under test is stageset's gating, not tik's own commands.
apply_migration_job() {
  local name="$1" code="$2"
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: ${name}
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      {
        apiVersion: 'batch/v1',
        kind: 'Job',
        metadata: { name: '${name}', namespace: '${ns}' },
        spec: {
          backoffLimit: 0,
          template: {
            spec: {
              restartPolicy: 'Never',
              containers: [{
                name: 'migrate',
                image: '${MIGRATION_JOB_IMAGE}',
                command: ['/bin/sh', '-c', 'exit ${code}'],
              }],
            },
          },
        },
      }
EOF
}

# apply_migrations <v3-job|""> — publishes the migration ladder as an
# ExternalArtifact for spec.migrationsSourceRef. The ladder is built with
# kurly.migrations.migration(), so this exercises lib/migrations.libsonnet on
# the real path (rendered by JaaS, consumed by stageset).
#
# The ladder GROWS rather than being replaced, the way a real one does: the V2
# rung stays in place once the V3 rung is added, so the walk also proves that
# re-publishing a ladder does not replay a rung already in the executed ledger.
# Pass an empty argument to publish the V2 rung alone.
#
# The boundaries are the DISCOVERED tags, so the walk always gates on versions
# that actually exist: a boundary naming an unreleased calver could never be
# crossed, and the phases below assert on real crossings.
apply_migrations() {
  local v3job="${1:-}"
  local v3rung=""
  if [ -n "$v3job" ]; then
    v3rung="kurly.migrations.migration('reprocess-on-${V3}', to='${V3}', stage='backend', actions=[{ name: 'reprocess-tickets', job: { sourceRef: { kind: 'ExternalArtifact', name: '${v3job}' } } }]),"
  fi
  kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: tik-migrations
  namespace: ${ns}
spec:
  serviceAccountName: default
  entryFile: main.jsonnet
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      [
        kurly.migrations.migration('reprocess-on-${V2}', to='${V2}', stage='backend', actions=[
          {
            name: 'reprocess-tickets',
            job: { sourceRef: { kind: 'ExternalArtifact', name: 'tik-migration-ok' } },
          },
        ]),
        ${v3rung}
      ]
  libraries:
    - { kind: JsonnetLibrary, name: kurly }
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

wait_ready() {
  local kind="$1" name="$2" polls="${3:-60}" i
  for i in $(seq 1 "$polls"); do
    [ "$(ready_status "$kind" "$name")" = "True" ] && { echo "${kind}/${name} Ready=True after ${i} polls"; return 0; }
    sleep 5
  done
  fail "${kind}/${name} never reached Ready=True"
}

# The image the backend Deployment currently runs.
deploy_image() {
  kubectl --namespace="$ns" get deploy tik \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="tik")].image}' 2>/dev/null || true
}

# The version stageset believes is deployed.
stageset_version() {
  kubectl --namespace="$ns" get stageset tik -o jsonpath='{.status.version}' 2>/dev/null || true
}

# The migration names stageset has recorded as executed, space-separated.
executed_migrations() {
  kubectl --namespace="$ns" get stageset tik \
    -o jsonpath='{range .status.executedMigrations[*]}{.name}{" "}{end}' 2>/dev/null || true
}

# stageset does not create the Job under the name the manifest carries: it
# appends a content digest of the action, so `tik-migration-ok` lands as
# `tik-migration-ok-2b182926`. Everything below therefore resolves the object by
# prefix — an exact-name lookup silently matches nothing forever.
job_name() {
  kubectl --namespace="$ns" get jobs \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | grep "^$1-" | head -1
}

# True once the named migration job has a successful completion.
job_succeeded() {
  local j
  j="$(job_name "$1")"
  [ -n "$j" ] || return 1
  [ "$(kubectl --namespace="$ns" get job "$j" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)" = "1" ]
}

# True once the named migration job has recorded a failure.
job_failed() {
  local j
  j="$(job_name "$1")"
  [ -n "$j" ] || return 1
  [ -n "$(kubectl --namespace="$ns" get job "$j" -o jsonpath='{.status.failed}' 2>/dev/null || true)" ]
}

# How many Pods a migration job has spawned — the idempotency probe. A migration
# that re-runs would create another pod generation.
job_pod_count() {
  kubectl --namespace="$ns" get pods \
    -o jsonpath='{range .items[*]}{.metadata.labels.job-name}{"\n"}{end}' 2>/dev/null \
    | grep -c "^$1-" || true
}

# The StageSet's Ready condition reason — MigrationDirty is the halt this
# scenario's blocking phase waits for.
stageset_reason() {
  kubectl --namespace="$ns" get stageset tik \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true
}

# Blocks until the Deployment carries an image containing $1; echoes 1 on timeout
# rather than failing, so the BLOCKING phase can assert the negative.
await_deploy_image() {
  local want="$1" polls="${2:-60}" i
  for i in $(seq 1 "$polls"); do
    case "$(deploy_image)" in *"${want}"*) return 0 ;; esac
    sleep 2
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
metadata: { name: kurly-tik-stageset-deployer }
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
# JaaS resolves absolute github.com/... imports by searching libraries whose file
# keys are full vendor paths, so key them that way — this tests the branch under
# review with no published artifact.
emit_kurly_library() {
  echo "apiVersion: jaas.metio.wtf/v1"
  echo "kind: JsonnetLibrary"
  echo "metadata: { name: kurly, namespace: ${ns} }"
  echo "spec:"
  echo "  files:"
  local f
  for f in main.libsonnet lib/*.libsonnet workloads/tik/backend.libsonnet; do
    echo "    \"github.com/metio/kurly/${f}\": |"
    sed 's/^/      /' "$f"
  done
}
emit_kurly_library | kubectl apply --server-side --force-conflicts --namespace="$ns" --filename=-

echo "== wait for the k8s-libsonnet OCI source to advertise an artifact =="
ok=false
for _ in $(seq 1 60); do
  [ -n "$(kubectl --namespace="$ns" get ocirepository/k8s-libsonnet -o jsonpath='{.status.artifact.url}' 2>/dev/null || true)" ] \
    && { ok=true; break; }
  sleep 3
done
[ "$ok" = true ] || fail "ocirepository/k8s-libsonnet never advertised an artifact"

# ---------------------------------------------------------------------------
# Phase 1 — BASELINE: the first install runs no migrations
# ---------------------------------------------------------------------------

echo "== phase 1: initial deploy at ${V1} =="
apply_snippet "$V1"
wait_ready jsonnetsnippet tik 90

# The ladder gates on V2 and V3. It is published BEFORE the first install on
# purpose: baselining must hold even when a migration for a future boundary is
# already visible to the controller.
apply_migration_job tik-migration-ok 0
apply_migrations ""
wait_ready jsonnetsnippet tik-migration-ok 90
wait_ready jsonnetsnippet tik-migrations 90

echo "== StageSet deploys the snippet, gating migrations on the version label =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tik, namespace: ${ns} }
spec:
  interval: 1m
  serviceAccountName: stageset-deployer
  # The deployed version is read from the workload's own label — the one
  # kurly.version() stamps on every rendered object.
  version:
    fromObject:
      stage: backend
      apiVersion: apps/v1
      kind: Deployment
      name: tik
  migrationsSourceRef:
    sourceRef: { kind: ExternalArtifact, name: tik-migrations }
  stages:
    - name: backend
      sourceRef: { name: tik }
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tik, namespace: ${ns} }
EOF

wait_ready stageset tik 90
if ! kubectl --namespace="$ns" rollout status deployment/tik --timeout=300s; then
  fail "initial rollout of deployment/tik never completed"
fi

echo "== assert: stageset baselined at ${V1} and ran nothing =="
for _ in $(seq 1 20); do
  [ "$(stageset_version)" = "$V1" ] && break
  sleep 3
done
[ "$(stageset_version)" = "$V1" ] \
  || fail "stageset recorded version '$(stageset_version)', expected the baseline ${V1}"

# The install is not a boundary crossing: the deployment already IS V1, so a
# migration gated on V2 must not have fired, and neither must anything else.
ran="$(executed_migrations)"
[ -z "${ran// /}" ] \
  || fail "the first install executed migrations (${ran}) — it must baseline silently"
[ "$(job_pod_count tik-migration-ok)" -eq 0 ] \
  || fail "the migration job ran during baselining"
echo "baselined at ${V1}, no migrations executed"

# ---------------------------------------------------------------------------
# Phase 2 — CROSSING: the boundary hop runs the migration
# ---------------------------------------------------------------------------

echo "== phase 2: hop ${V1} -> ${V2}, crossing the migration boundary =="
apply_snippet "$V2"

echo "== assert: the migration job runs =="
completed=false
for _ in $(seq 1 60); do
  job_succeeded tik-migration-ok && { completed=true; break; }
  sleep 5
done
[ "$completed" = true ] || fail "the migration job never completed on the ${V1} -> ${V2} hop"

echo "== assert: the stage advanced to ${V2} after the migration =="
await_deploy_image "$V2" 60 || fail "stageset never applied the ${V2} image after the migration"
if ! kubectl --namespace="$ns" rollout status deployment/tik --timeout=300s; then
  fail "rollout to ${V2} never completed"
fi

for _ in $(seq 1 20); do
  case " $(executed_migrations) " in *" reprocess-on-${V2} "*) break ;; esac
  sleep 3
done
case " $(executed_migrations) " in
  *" reprocess-on-${V2} "*) echo "migration reprocess-on-${V2} recorded as executed" ;;
  *) fail "stageset did not record reprocess-on-${V2} (executed: $(executed_migrations))" ;;
esac

# ---------------------------------------------------------------------------
# Phase 3 — IDEMPOTENCY: a re-render does not re-run it
# ---------------------------------------------------------------------------

echo "== phase 3: re-render at ${V2} — an executed migration must not re-run =="
pods_before="$(job_pod_count tik-migration-ok)"
apply_snippet "$V2"
sleep 30 # let at least one reconcile pass over the unchanged version
pods_after="$(job_pod_count tik-migration-ok)"
[ "$pods_before" = "$pods_after" ] \
  || fail "the migration re-ran on a no-op re-render (${pods_before} -> ${pods_after} job pods)"
echo "migration not re-run (${pods_after} job pod, unchanged)"

# ---------------------------------------------------------------------------
# Phase 4 — BLOCKING: a failing migration halts its stage
# ---------------------------------------------------------------------------

echo "== phase 4: hop ${V2} -> ${V3} behind a FAILING migration =="
apply_migration_job tik-migration-fail 1
wait_ready jsonnetsnippet tik-migration-fail 90
apply_migrations tik-migration-fail
apply_snippet "$V3"

echo "== assert: the failing migration is observed =="
observed=false
for _ in $(seq 1 60); do
  job_failed tik-migration-fail && { observed=true; break; }
  sleep 5
done
[ "$observed" = true ] || fail "the failing migration job never reported a failure"

# stageset retries a failing migration a few times and then deliberately stops,
# halting the stage as MigrationDirty rather than retrying a destructive action
# forever. Waiting for that terminal reason (rather than sleeping) makes the
# blocking assertion below deterministic.
echo "== assert: the stage halts as MigrationDirty =="
dirty=false
for _ in $(seq 1 60); do
  [ "$(stageset_reason)" = "MigrationDirty" ] && { dirty=true; break; }
  sleep 5
done
[ "$dirty" = true ] \
  || fail "the failing migration never halted the stage (reason: $(stageset_reason))"

# The point of the whole phase: the stage must NOT advance while its migration
# is failing. A Deployment carrying V3 here means stageset applied manifests it
# was supposed to gate — the exact bug this scenario exists to catch.
echo "== assert: the backend stage is BLOCKED at ${V2} =="
if await_deploy_image "$V3" 30; then
  fail "stageset advanced deployment/tik to ${V3} despite a failed migration"
fi
case "$(deploy_image)" in
  *"${V2}"*) echo "stage correctly blocked — deployment still on ${V2}" ;;
  *) fail "deployment left an unexpected image while blocked: $(deploy_image)" ;;
esac

echo "== repair the migration and clear the halt (the documented recovery) =="
# A dirty halt does not clear itself: fixing the job is necessary but NOT
# sufficient, because the controller has stopped retrying on purpose. The
# operator republishes the fixed job and then explicitly asks for a reconcile —
# the runbook's recovery, and the reason this phase exists rather than a plain
# "it fails" assertion.
#   https://stageset.projects.metio.wtf/runbooks/migrationdirty/
kubectl --namespace="$ns" delete job "$(job_name tik-migration-fail)" --ignore-not-found
apply_migration_job tik-migration-fail 0
wait_ready jsonnetsnippet tik-migration-fail 60

# Nothing has asked the controller to try again yet, so the stage must still be
# sitting at V2 — proof the halt is a real stop rather than a slow retry.
case "$(deploy_image)" in
  *"${V2}"*) echo "still halted at ${V2} with the job repaired — the halt needs an explicit clear" ;;
  *) fail "deployment moved off ${V2} before the halt was cleared: $(deploy_image)" ;;
esac

kubectl --namespace="$ns" annotate stageset tik \
  "reconcile.fluxcd.io/requestedAt=$(date +%s)" --overwrite

await_deploy_image "$V3" 90 || fail "stageset never advanced to ${V3} after the halt was cleared"
if ! kubectl --namespace="$ns" rollout status deployment/tik --timeout=300s; then
  fail "rollout to ${V3} never completed after the migration was repaired"
fi

# The ${V2} rung is still in the ladder and still executed: walking past it must
# not replay it, or every ladder would re-run its whole history on each release.
[ "$(job_pod_count tik-migration-ok)" -eq "$pods_after" ] \
  || fail "the already-executed ${V2} migration replayed while crossing to ${V3}"

echo "tik walked ${V1} -> ${V2} -> ${V3} through Flux+JaaS+stageset: baselined silently, ran its migration once, and blocked the stage on a failing one"
