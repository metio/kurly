// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// k8up/restore — writes a repository's contents back, as a K8up `Restore`
// custom resource. The counterpart to k8up/schedule.libsonnet and the half that
// matters: a backup nobody has restored is a guess. Import it, adapt with the
// parameters below, and render with kurly.list:
//
//   local restore = import 'github.com/metio/kurly/workloads/k8up/restore.libsonnet';
//   kurly.list(restore(name='recover', claim='nextcloud',
//                      s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' }))
//
// PREREQUISITE: the K8up operator must be installed in the cluster, and the
// repository Secret must exist in this namespace — the same Secret the schedule
// reads.
//
// A Restore runs ONCE, the moment it is applied, and K8up offers no way to stage
// one — `Restore.spec` has no field that holds it back. The only way to keep a
// recovery from starting is not to apply the manifest, so treat rendering one as
// the act of starting it.
//
// Restoring into a claim ('folder') puts the data back where the application
// expects it; restoring to S3 puts a tarball somewhere a person can inspect it,
// which is what to do when the question is what the backup contains rather than
// putting it back.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'kurly.metio.wtf/version': version,
};

function(
  name='restore',
  claim='data',
  s3={ endpoint: 'http://seaweedfs:8333', bucket: 'backups' },
  repoPasswordSecret='k8up-repository',
  repoPasswordKey='password',
  snapshot=null,
  restoreTo=null,
  resources=null,
  podSecurityContext=null,
  backend={},
  restoreMethod={},
  labels={},
  annotations={},
)
  assert s3 != null || backend != {} :
         'k8up/restore: give s3 (endpoint, bucket, and the Secret refs for its credentials) or a full backend — there is nothing to restore from otherwise';
  assert (claim != null) != (restoreTo != null) :
         'k8up/restore: give either claim (restore into a PersistentVolumeClaim, which is recovery) or restoreTo (write a tarball to object storage, which is inspection), not both and not neither';
  {
    assert !std.objectHasAll(self, 'config') :
           'k8up/restore: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, resources, podSecurityContext), or the `backend`/`restoreMethod` pass-throughs.",
    restore: {
      apiVersion: 'k8up.io/v1',
      kind: 'Restore',
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
        // Unset restores the most recent snapshot, which is what a recovery
        // wants. Naming one recovers a specific point — the way past a
        // corruption that was itself backed up.
        snapshot: snapshot,
        restoreMethod: std.prune({
          folder: (if claim == null then null else { claimName: claim }),
          s3: restoreTo,
        }) + restoreMethod,
        resources: resources,
        podSecurityContext: podSecurityContext,
      }),
    },
  }
