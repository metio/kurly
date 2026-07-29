#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the half of a backup that matters, K8up's way. Same proof as
# volsync-restore.sh — write a known file, back it up, destroy the volume,
# restore it, read the file back — because a backup nobody has restored is a
# guess, and a job that exited zero proves only that bytes left.
#
# What differs is the shape being tested. K8up backs up a NAMESPACE rather than a
# claim: the Schedule finds the volumes itself, so this scenario never names the
# claim to back up. That is the property worth proving, since it is the reason to
# choose K8up over VolSync — a volume created tomorrow is covered without anybody
# editing anything.
#
# The scenario drives a Backup directly rather than waiting for the Schedule's
# cron: the Schedule is applied and asserted to produce the CronJobs it promises,
# and an on-demand Backup does the same work at once instead of on the hour.
cd "$(dirname "$0")/../../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

# renovate: datasource=helm depName=k8up registryUrl=https://k8up-io.github.io/k8up
K8UP_VERSION="4.8.0"

ns=kurly-k8up-restore
bucket=kurly-k8up
ep="http://seaweedfs-0.seaweedfs-headless.${ns}.svc:8333"
canary="restored-by-kurly-$(date +%s)"

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::backup and restore state"
  kubectl --namespace="$ns" get schedule,backup,restore,cronjob,job,pvc,pods -o wide 2>/dev/null || true
  echo "--- Backup status ---"
  kubectl --namespace="$ns" get backup backup-once -o yaml 2>/dev/null | tail -40 || true
  echo "--- Restore status ---"
  kubectl --namespace="$ns" get restore restore-once -o yaml 2>/dev/null | tail -40 || true
  echo "--- job logs ---"
  kubectl --namespace="$ns" logs --selector=k8upjob=true --tail=60 --prefix 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

echo "== install the K8up operator ${K8UP_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/k8up-io/k8up/releases/download/k8up-${K8UP_VERSION}/k8up-crd.yaml" \
  || fail "the K8up CRDs did not install"
helm repo add k8up-io https://k8up-io.github.io/k8up >/dev/null
helm repo update >/dev/null
helm install k8up k8up-io/k8up \
  --namespace k8up-system --create-namespace --wait --timeout 5m \
  || fail "the K8up operator never became Ready"

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

# The repository Secret kurly deliberately does not author. The keys are the ones
# the catalog's secretKeys names: K8up reads the repository password and the S3
# credentials from the same Secret.
kubectl --namespace="$ns" create secret generic k8up-repository \
  --from-literal=password=kurly-e2e-restic \
  --from-literal=username=kurlytest

# ---------------------------------------------------------------------------
# A volume with something in it worth losing. Never named to K8up.
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
# The schedule, from kurly's own recipe. It names no claim.
# ---------------------------------------------------------------------------

echo "== apply the k8up/schedule recipe =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local schedule = import 'workloads/k8up/schedule.libsonnet';
k.list(schedule(
  name='tenant',
  s3={ endpoint: '${ep}', bucket: '${bucket}' },
))" | kubectl apply --namespace="$ns" --filename=- || fail "the Schedule did not apply"

echo "== the schedule produces the runs it promises =="
# A Schedule that reconciles into CronJobs is the operator agreeing to the
# backup, prune and check cadences the recipe asked for. Nothing here waits for
# a cron to fire; the on-demand Backup below does that work now.
jobs=0
for _ in $(seq 1 30); do
  jobs="$(kubectl --namespace="$ns" get cronjob --no-headers 2>/dev/null | wc -l)"
  echo "cronjobs: ${jobs}"
  [ "$jobs" -ge 3 ] && break
  sleep 5
done
[ "$jobs" -ge 3 ] \
  || fail "the Schedule never produced its backup, prune and check runs (saw ${jobs} CronJobs)"

echo "== back the namespace up now =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: k8up.io/v1
kind: Backup
metadata: { name: backup-once, namespace: ${ns} }
spec:
  backend:
    repoPasswordSecretRef: { name: k8up-repository, key: password }
    s3:
      endpoint: ${ep}
      bucket: ${bucket}
      accessKeyIDSecretRef: { name: k8up-repository, key: username }
      secretAccessKeySecretRef: { name: k8up-repository, key: password }
EOF

echo "== wait for the backup to finish =="
finished=false
for _ in $(seq 1 60); do
  cond="$(kubectl --namespace="$ns" get backup backup-once -o jsonpath='{.status.finished}' 2>/dev/null || true)"
  echo "finished: ${cond:-<pending>}"
  [ "$cond" = "true" ] && { finished=true; break; }
  sleep 10
done
[ "$finished" = true ] || fail "the backup never finished"

# ---------------------------------------------------------------------------
# Destroy the volume. Everything after this depends on the repository alone.
# ---------------------------------------------------------------------------

echo "== destroy the volume the canary lived on, and make a fresh one =="
kubectl --namespace="$ns" delete pvc data --wait=true --timeout=120s \
  || fail "could not delete the source volume"
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: ${ns} }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 128Mi } }
EOF

echo "== restore through k8up/restore =="
jsonnet -J vendor -e "
local k = import 'github.com/metio/kurly/main.libsonnet';
local restore = import 'workloads/k8up/restore.libsonnet';
k.list(restore(
  name='restore-once',
  claim='data',
  s3={ endpoint: '${ep}', bucket: '${bucket}' },
))" | kubectl apply --namespace="$ns" --filename=- || fail "the Restore did not apply"

echo "== wait for the restore to finish =="
restored=false
for _ in $(seq 1 60); do
  cond="$(kubectl --namespace="$ns" get restore restore-once -o jsonpath='{.status.finished}' 2>/dev/null || true)"
  echo "finished: ${cond:-<pending>}"
  [ "$cond" = "true" ] && { restored=true; break; }
  sleep 10
done
[ "$restored" = true ] || fail "the restore never finished"

# ---------------------------------------------------------------------------
# The assertion: the bytes are back, and they are the right bytes.
# ---------------------------------------------------------------------------

echo "== read the canary back out of the restored volume =="
kubectl apply --namespace="$ns" --filename=- <<EOF
apiVersion: v1
kind: Pod
metadata: { name: reader, namespace: ${ns} }
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: docker.io/library/busybox:1.37.0
      command: [sh, -c, "find /data -name canary.txt -exec cat {} +"]
      volumeMounts: [{ name: data, mountPath: /data }]
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: data }
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
helm uninstall k8up --namespace k8up-system >/dev/null 2>&1 || true
kubectl delete namespace k8up-system --ignore-not-found --wait=false >/dev/null 2>&1 || true
kurly::cleanup_workload "$ns" k8up
echo "k8up-restore: OK"
