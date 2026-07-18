#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the pairing the two workloads exist to enable: a cnpg-cluster backs up
# to a seaweedfs S3 gateway, both in the same cluster. Neither the render gates
# nor the per-workload e2es can show this — it is the seam between them, and only
# a live backup crossing it proves the seam holds: PostgreSQL's WAL and a base
# backup written through CNPG's barman, over S3, into SeaweedFS's volume.
#
# The proof is CNPG's own: a Backup that reaches phase `completed` is barman
# confirming it uploaded to the object store successfully — so a green backup IS
# the assertion that the S3 write path works end to end. The scenario then lists
# the bucket to show the objects physically landed.
#
# SeaweedFS runs with no identities (anonymous access), so it accepts the barman
# requests without an auth-config dance; the cluster still carries dummy S3
# credentials because barmanObjectStore requires them configured, and SeaweedFS
# ignores them in this mode. A real deployment puts credentials on both sides.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.30.0"

ns=kurly-cnpg-backup
bucket=kurly-backups
ep="http://seaweedfs-0.seaweedfs-headless.${ns}.svc:8333"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::backup pairing state"
  kubectl --namespace="$ns" get statefulset,cluster,backup,pods -o wide 2>/dev/null || true
  echo "--- cluster status (ContinuousArchiving is where a WAL-to-S3 failure shows) ---"
  kubectl --namespace="$ns" get cluster postgres -o jsonpath='{.status.conditions}' 2>/dev/null || true
  echo
  echo "--- backup status ---"
  kubectl --namespace="$ns" get backup kurly-backup -o yaml 2>/dev/null | tail -40 || true
  echo "--- seaweedfs log ---"
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/name=seaweedfs --tail=40 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install the CloudNativePG operator ${CNPG_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml"
kubectl --namespace=cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s

kurly::vendor
kurly::namespace "$ns"

# ---------------------------------------------------------------------------
# The S3 target FIRST — the bucket must exist before the cluster archives WAL.
# ---------------------------------------------------------------------------

echo "== deploy the seaweedfs S3 target =="
kurly::render workloads/seaweedfs/server.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-
kubectl --namespace="$ns" rollout status statefulset/seaweedfs --timeout=300s \
  || fail "the seaweedfs S3 target never became Ready"

echo "== a curl client, and pre-create the backup bucket =="
kubectl --namespace="$ns" run s3-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/s3-client --timeout=120s \
  || fail "the S3 client pod never became Ready"
# barman does not create the bucket; anonymous SeaweedFS lets us PUT it directly.
kubectl --namespace="$ns" exec s3-client -- curl -sf -X PUT "${ep}/${bucket}" >/dev/null 2>&1 \
  || fail "could not create the backup bucket on seaweedfs"

# barmanObjectStore requires credentials configured even when the store ignores
# them; SeaweedFS with no identities accepts the requests regardless.
kubectl --namespace="$ns" create secret generic s3creds \
  --from-literal=ACCESS_KEY_ID=kurlytest --from-literal=ACCESS_SECRET_KEY=kurlytestsecret

# ---------------------------------------------------------------------------
# The database, pointed at that S3 target through the workload's backup param.
# ---------------------------------------------------------------------------

echo "== deploy a PostgreSQL cluster that backs up to seaweedfs =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local cnpg = import 'workloads/cnpg-cluster/cluster.libsonnet';
k.list(cnpg(
  instances=1,
  storageSize='256Mi',
  backup={
    barmanObjectStore: {
      destinationPath: 's3://${bucket}/',
      endpointURL: '${ep}',
      s3Credentials: {
        accessKeyId: { name: 's3creds', key: 'ACCESS_KEY_ID' },
        secretAccessKey: { name: 's3creds', key: 'ACCESS_SECRET_KEY' },
      },
      wal: { compression: 'gzip' },
      data: { compression: 'gzip' },
    },
  },
))" | kubectl apply --namespace="$ns" --filename=-

echo "== wait for the PostgreSQL cluster to become healthy =="
healthy=false
for _ in $(seq 1 72); do
  phase="$(kubectl --namespace="$ns" get cluster postgres -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "cluster phase: ${phase:-<pending>}"
  case "$phase" in *healthy*) healthy=true; break ;; esac
  sleep 5
done
[ "$healthy" = true ] || fail "the PostgreSQL cluster never became healthy"

# ---------------------------------------------------------------------------
# The backup — the crossing of the seam.
# ---------------------------------------------------------------------------

echo "== trigger an on-demand base backup to seaweedfs =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: kurly-backup, namespace: ${ns} }
spec:
  cluster: { name: postgres }
EOF

echo "== wait for the backup to complete =="
# `completed` is barman confirming the upload to S3 succeeded — the proof the WAL
# and base backup crossed into SeaweedFS. `failed` means the S3 write path broke.
done_ok=false
for _ in $(seq 1 72); do
  phase="$(kubectl --namespace="$ns" get backup kurly-backup -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  echo "backup phase: ${phase:-<pending>}"
  case "$phase" in
    completed) done_ok=true; break ;;
    failed) fail "the backup failed — the cluster could not write to the seaweedfs S3 target" ;;
  esac
  sleep 5
done
[ "$done_ok" = true ] || fail "the backup never completed"

echo "== assert: the backup objects landed in the bucket =="
# List the bucket over S3 and confirm the cluster's backup artifacts are there —
# the objects physically stored on the SeaweedFS volume, not just a green status.
listing="$(kubectl --namespace="$ns" exec s3-client -- curl -sf "${ep}/${bucket}?list-type=2" 2>/dev/null || true)"
case "$listing" in
  *postgres*) echo "  the bucket holds the cluster's backup objects" ;;
  *) fail "the bucket has no backup objects (listing: ${listing:-<empty>})" ;;
esac

echo "cnpg-cluster backed up to seaweedfs on a live cluster: the base backup crossed CNPG's barman → S3 → SeaweedFS's volume and the objects are in the bucket"
