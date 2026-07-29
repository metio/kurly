#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the half of a backup that matters. A backup nobody has restored is a
# guess, and a scenario asserting that a backup job exited zero would be testing
# the wrong half: it proves bytes left the volume, not that they can come back.
#
# So this writes a known file into a PersistentVolume, backs the volume up to a
# seaweedfs S3 gateway through volsync/backup, DESTROYS the volume, restores it
# through volsync/restore into a fresh one, and reads the file back. The
# assertion is the file's contents — the only evidence that survives the volume
# it came from.
#
# copyMethod=Direct throughout, deliberately: Snapshot needs a CSI driver with a
# VolumeSnapshotClass, which kind's default storage does not provide, and the
# thing under test here is the restic round trip rather than the snapshotter.
# Nothing writes to the volume during the window, so Direct is honest here in a
# way it would not be for a running database.
cd "$(dirname "$0")/../../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=helm depName=volsync registryUrl=https://backube.github.io/helm-charts/
VOLSYNC_VERSION="0.13.0"

ns=kurly-volsync-restore
bucket=kurly-volsync
ep="http://seaweedfs-0.seaweedfs-headless.${ns}.svc:8333"
canary="restored-by-kurly-$(date +%s)"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::backup and restore state"
  kubectl --namespace="$ns" get replicationsource,replicationdestination,pvc,pods -o wide 2>/dev/null || true
  echo "--- ReplicationSource status ---"
  kubectl --namespace="$ns" get replicationsource data -o yaml 2>/dev/null | tail -40 || true
  echo "--- ReplicationDestination status ---"
  kubectl --namespace="$ns" get replicationdestination restore -o yaml 2>/dev/null | tail -40 || true
  echo "--- mover logs ---"
  kubectl --namespace="$ns" logs --selector=app.kubernetes.io/created-by=volsync --tail=60 --prefix 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install the VolSync operator ${VOLSYNC_VERSION} =="
helm repo add backube https://backube.github.io/helm-charts/ >/dev/null
helm repo update >/dev/null
helm install volsync backube/volsync \
  --version "$VOLSYNC_VERSION" --namespace volsync-system --create-namespace --wait --timeout 5m \
  || fail "the VolSync operator never became Ready"

kurly::vendor
kurly::namespace "$ns"

echo "== deploy the seaweedfs S3 target =="
kurly::render workloads/seaweedfs/server.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-
kubectl --namespace="$ns" rollout status statefulset/seaweedfs --timeout=300s \
  || fail "the seaweedfs S3 target never became Ready"

echo "== a curl client, and pre-create the repository bucket =="
kubectl --namespace="$ns" run s3-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/s3-client --timeout=120s \
  || fail "the S3 client pod never became Ready"
kubectl --namespace="$ns" exec s3-client -- curl -sf -X PUT "${ep}/${bucket}" >/dev/null 2>&1 \
  || fail "could not create the repository bucket on seaweedfs"

# The repository Secret kurly deliberately does not author — the keys are the
# ones the catalog's secretKeys names. SeaweedFS runs with no identities here and
# ignores the credentials; restic still requires them present.
kubectl --namespace="$ns" create secret generic restic-repository \
  --from-literal=RESTIC_REPOSITORY="s3:${ep}/${bucket}" \
  --from-literal=RESTIC_PASSWORD=kurly-e2e-restic \
  --from-literal=AWS_ACCESS_KEY_ID=kurlytest \
  --from-literal=AWS_SECRET_ACCESS_KEY=kurlytestsecret

# ---------------------------------------------------------------------------
# A volume with something in it worth losing.
# ---------------------------------------------------------------------------

echo "== create a volume and write the canary into it =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: ${ns} }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 128Mi } }
EOF
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: v1
kind: Pod
metadata: { name: writer, namespace: ${ns} }
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: docker.io/library/busybox:1.37.0
      command: [sh, -c, "echo '${canary}' > /data/canary.txt && sync"]
      volumeMounts: [{ name: data, mountPath: /data }]
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: data }
EOF
kubectl --namespace="$ns" wait --for=condition=Ready=false --timeout=120s pod/writer >/dev/null 2>&1 || true
for _ in $(seq 1 24); do
  phase="$(kubectl --namespace="$ns" get pod writer -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [ "$phase" = Succeeded ] && break
  [ "$phase" = Failed ] && fail "the writer pod failed before writing the canary"
  sleep 5
done
[ "$(kubectl --namespace="$ns" get pod writer -o jsonpath='{.status.phase}')" = Succeeded ] \
  || fail "the canary was never written"
kubectl --namespace="$ns" delete pod writer --wait=true

# ---------------------------------------------------------------------------
# The backup, from kurly's own recipe.
# ---------------------------------------------------------------------------

echo "== back the volume up through volsync/backup =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local backup = import 'workloads/volsync/backup.libsonnet';
k.list(backup(
  name='data',
  sourcePVC='data',
  repository='restic-repository',
  schedule=null,
  manual='backup-once',
  copyMethod='Direct',
))" | kubectl apply --namespace="$ns" --filename=- || fail "the ReplicationSource did not apply"

echo "== wait for the backup to complete =="
# VolSync reports a manual trigger as completed by echoing its name into
# status.lastManualSync — the mover's own confirmation that restic finished.
synced=false
for _ in $(seq 1 60); do
  last="$(kubectl --namespace="$ns" get replicationsource data -o jsonpath='{.status.lastManualSync}' 2>/dev/null || true)"
  echo "lastManualSync: ${last:-<pending>}"
  [ "$last" = "backup-once" ] && { synced=true; break; }
  sleep 10
done
[ "$synced" = true ] || fail "the backup never completed"

# ---------------------------------------------------------------------------
# Destroy the volume. Everything after this depends on the repository alone.
# ---------------------------------------------------------------------------

echo "== destroy the volume the canary lived on =="
kubectl --namespace="$ns" delete pvc data --wait=true --timeout=120s \
  || fail "could not delete the source volume"

echo "== restore through volsync/restore =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local restore = import 'workloads/volsync/restore.libsonnet';
k.list(restore(
  name='restore',
  repository='restic-repository',
  capacity='128Mi',
  manual='restore-once',
  copyMethod='Direct',
  destinationPVC=null,
))" | kubectl apply --namespace="$ns" --filename=- || fail "the ReplicationDestination did not apply"

echo "== wait for the restore to complete =="
restored=false
for _ in $(seq 1 60); do
  last="$(kubectl --namespace="$ns" get replicationdestination restore -o jsonpath='{.status.lastManualSync}' 2>/dev/null || true)"
  echo "lastManualSync: ${last:-<pending>}"
  [ "$last" = "restore-once" ] && { restored=true; break; }
  sleep 10
done
[ "$restored" = true ] || fail "the restore never completed"

# ---------------------------------------------------------------------------
# The assertion: the bytes are back, and they are the right bytes.
# ---------------------------------------------------------------------------

target="$(kubectl --namespace="$ns" get replicationdestination restore -o jsonpath='{.status.latestImage.name}' 2>/dev/null || true)"
[ -n "$target" ] || target=volsync-restore-dest
echo "== read the canary back out of ${target} =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: v1
kind: Pod
metadata: { name: reader, namespace: ${ns} }
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: docker.io/library/busybox:1.37.0
      command: [sh, -c, "cat /data/canary.txt"]
      volumeMounts: [{ name: data, mountPath: /data }]
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: ${target} }
EOF
for _ in $(seq 1 24); do
  phase="$(kubectl --namespace="$ns" get pod reader -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in Succeeded | Failed) break ;; esac
  sleep 5
done
got="$(kubectl --namespace="$ns" logs pod/reader 2>/dev/null | tr -d '\r\n')"
[ "$got" = "$canary" ] \
  || fail "the restored volume does not carry the canary — expected '${canary}', read '${got:-<nothing>}'"

echo "== the canary survived the volume it was written to: ${got} =="

echo "== cleanup =="
helm uninstall volsync --namespace volsync-system >/dev/null 2>&1 || true
kubectl delete namespace volsync-system --ignore-not-found --wait=false >/dev/null 2>&1 || true
kurly::cleanup_workload "$ns" volsync
echo "volsync-restore: OK"
