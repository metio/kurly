// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// k8up/backup — one snapshot of every PersistentVolume in a namespace, taken
// now, as a K8up `Backup` custom resource. The one-off counterpart to
// k8up/schedule.libsonnet: a Schedule protects a namespace over time, a Backup
// answers "capture this exact moment", which is what a snapshot taken
// immediately before an update is. Import it, adapt with the parameters below,
// and render with kurly.list:
//
//   local backup = import 'github.com/metio/kurly/workloads/k8up/backup.libsonnet';
//   kurly.list(backup(name='pre-update', tags=['pre-update', 'v2.3.1'],
//                     s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' }))
//
// PREREQUISITE: the K8up operator must be installed in the cluster, and the
// repository Secret must exist in this namespace — the same Secret the schedule
// and the restore read.
//
// A Backup runs the moment it is applied and then FINISHES. K8up gives it no
// field to hold it back, which is the right shape here rather than a limitation:
// something that applies it can wait for the run to end and act on the outcome.
//
// Waiting on one means watching for completion, NOT readiness — a Backup never
// reports Ready. It finishes with `status.finished: true` and a `Completed`
// condition whose reason is `Succeeded` or `Failed`. Anything that waits for a
// Ready condition instead waits forever.
//
// `tags` is what makes a snapshot findable afterwards. Restic selects by tag, so
// an untagged snapshot can only be picked out by timestamp — which is guesswork
// at the moment somebody needs it most. Tag the reason it was taken.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'kurly.metio.wtf/version': version,
};

function(
  name='backup',
  s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' },
  repoPasswordSecret='k8up-repository',
  repoPasswordKey='password',
  tags=[],
  activeDeadlineSeconds=null,
  failedJobsHistoryLimit=3,
  successfulJobsHistoryLimit=1,
  promURL=null,
  statsURL=null,
  resources=null,
  podSecurityContext=null,
  podConfigRef=null,
  volumes=[],
  backend={},
  labels={},
  annotations={},
)
  assert s3 != null || backend != {} :
         'k8up/backup: give s3 (endpoint, bucket, and the Secret refs for its credentials) or a full backend — a snapshot with nowhere to write is a snapshot that does not exist';
  assert s3 == null || (std.objectHas(s3, 'endpoint') && std.objectHas(s3, 'bucket')) :
         'k8up/backup: s3 needs at least endpoint and bucket';
  {
    assert !std.objectHasAll(self, 'config') :
           'k8up/backup: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, resources, podSecurityContext), or the `backend` pass-through.",
    backup: {
      apiVersion: 'k8up.io/v1',
      kind: 'Backup',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        backend: std.prune({
          repoPasswordSecretRef: {
            name: repoPasswordSecret,
            key: repoPasswordKey,
          },
          s3: (
            if s3 == null then null
            else {
              accessKeyIDSecretRef: { name: repoPasswordSecret, key: 'username' },
              secretAccessKeySecretRef: { name: repoPasswordSecret, key: 'password' },
            } + s3
          ),
        }) + backend,
        tags: tags,
        // A backup that hangs does not fail, and something gating an update on
        // this one would wait for it forever. A deadline turns that into an
        // outcome the caller can act on.
        activeDeadlineSeconds: activeDeadlineSeconds,
        failedJobsHistoryLimit: failedJobsHistoryLimit,
        successfulJobsHistoryLimit: successfulJobsHistoryLimit,
        promURL: promURL,
        statsURL: statsURL,
        resources: resources,
        podSecurityContext: podSecurityContext,
        podConfigRef: podConfigRef,
        volumes: volumes,
      }),
    },
  }
