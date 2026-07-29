// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// k8up/schedule — backs up every PersistentVolume in a namespace on a schedule,
// as a K8up `Schedule` custom resource, and keeps the repository healthy with
// the prune and check runs a restic repository needs. Like cnpg-cluster, this
// authors the CR directly: the backup pods belong to the K8up operator. Import
// it, adapt with the parameters below, and render with kurly.list:
//
//   local schedule = import 'github.com/metio/kurly/workloads/k8up/schedule.libsonnet';
//   kurly.list(schedule(name='tenant', s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' }))
//
// PREREQUISITE: the K8up operator must be installed in the cluster, and the
// repository Secret must exist in this namespace (see secretKeys in the catalog
// — kurly authors no Secret).
//
// This is the per-NAMESPACE shape, which is how K8up differs from VolSync's
// per-claim one: a Schedule backs up every PVC it finds, so a new volume is
// protected the moment it appears rather than when somebody remembers to
// declare it. A volume to leave out is annotated `k8up.io/backup: "false"` on
// its claim.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='backup',
  s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' },
  repoPasswordSecret='k8up-repository',
  repoPasswordKey='password',
  backupSchedule='0 2 * * *',
  pruneSchedule='0 3 * * 0',
  checkSchedule='0 4 * * 0',
  archiveSchedule=null,
  keepDaily=7,
  keepWeekly=4,
  keepMonthly=6,
  retention={},
  failedJobsHistoryLimit=3,
  successfulJobsHistoryLimit=1,
  resources=null,
  podSecurityContext=null,
  backend={},
  labels={},
  annotations={},
)
  assert s3 != null || backend != {} :
         'k8up/schedule: give s3 (endpoint, bucket, and the Secret refs for its credentials) or a full backend — a repository with nowhere to write is a schedule that fails every night';
  assert s3 == null || (std.objectHas(s3, 'endpoint') && std.objectHas(s3, 'bucket')) :
         'k8up/schedule: s3 needs at least endpoint and bucket';
  // A repository that is never pruned grows without bound, and one that is never
  // checked can be corrupt for months before a restore finds out. Both are
  // scheduled by default and either can be turned off deliberately; neither
  // should be off by accident.
  assert pruneSchedule != null || retention == {} :
         'k8up/schedule: a retention policy without a prune schedule never deletes anything — set pruneSchedule, or drop the retention';
  {
    assert !std.objectHasAll(self, 'config') :
           'k8up/schedule: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, resources, podSecurityContext), or the `backend` pass-through for anything else K8up accepts.",
    schedule: {
      apiVersion: 'k8up.io/v1',
      kind: 'Schedule',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        // Where the repository lives, and the password that encrypts it. The
        // shorthand covers the S3 case every object store answers; `backend` is
        // merged last and takes anything K8up accepts — Azure, GCS, B2, Swift,
        // rest, or an S3 field kurly does not model.
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
        backup: std.prune({
          schedule: backupSchedule,
          failedJobsHistoryLimit: failedJobsHistoryLimit,
          successfulJobsHistoryLimit: successfulJobsHistoryLimit,
          resources: resources,
          podSecurityContext: podSecurityContext,
        }),
        // Pruning is what makes the retention policy real: it is the run that
        // deletes what the policy no longer keeps. Passed as K8up's own
        // `retention` schema, with the three intervals a nightly backup
        // ordinarily wants named, and `retention` merged over them for the rest
        // (keepHourly, keepYearly, keepLast, keepTags).
        prune: (
          if pruneSchedule == null then null
          else {
            schedule: pruneSchedule,
            retention: std.prune({
              keepDaily: keepDaily,
              keepWeekly: keepWeekly,
              keepMonthly: keepMonthly,
            }) + retention,
          }
        ),
        // A check verifies the repository's own integrity. It is the run that
        // notices a repository has rotted before a restore does.
        check: (if checkSchedule == null then null else { schedule: checkSchedule }),
        // An archive copies snapshots to a second, usually colder repository.
        // Off unless asked for: it doubles the storage bill and answers a
        // question — long-term retention elsewhere — that most namespaces do not
        // have.
        archive: (if archiveSchedule == null then null else { schedule: archiveSchedule }),
      }),
    },
  }
