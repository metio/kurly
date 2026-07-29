// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// volsync/restore — writes a repository's contents back into a PersistentVolume,
// as a VolSync `ReplicationDestination` custom resource. The counterpart to
// volsync/backup.libsonnet and the half that matters: a backup nobody has
// restored is a guess. Import it, adapt with the parameters below, and render
// with kurly.list:
//
//   local restore = import 'github.com/metio/kurly/workloads/volsync/restore.libsonnet';
//   kurly.list(restore(name='nextcloud', repository='nextcloud-restic', capacity='20Gi'))
//
// PREREQUISITE: the VolSync operator must be installed in the cluster, and the
// repository Secret must exist in this namespace — the same Secret the backup
// side reads.
//
// By default this restores the LATEST snapshot into a volume VolSync provisions,
// and does it once: `manual` names the trigger, and the operator runs when that
// name changes rather than on a clock. Restoring on a schedule is for keeping a
// warm standby copy, not for recovering, and is deliberately not the default.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='restore',
  repository='restic-repository',
  capacity='10Gi',
  manual='restore-once',
  schedule=null,
  copyMethod='Snapshot',
  destinationPVC=null,
  accessModes=['ReadWriteOnce'],
  storageClassName=null,
  volumeSnapshotClassName=null,
  cacheCapacity=null,
  restoreAsOf=null,
  previous=null,
  cleanupCachePVC=true,
  cleanupTempPVC=true,
  moverSecurityContext=null,
  restic={},
  labels={},
  annotations={},
)
  // VolSync provisions the volume it restores into unless handed one, and it
  // cannot provision without a size. Naming an existing claim answers the same
  // question, so exactly one of the two must be present.
  assert (capacity != null) != (destinationPVC != null) :
         'volsync/restore: give either capacity (VolSync provisions the volume it restores into) or destinationPVC (restore into a claim that already exists), not both and not neither';
  assert std.member(['Snapshot', 'Direct', 'None'], copyMethod) :
         "volsync/restore: copyMethod must be one of Snapshot, Direct, None — got '" + copyMethod + "'";
  assert manual == null || schedule == null :
         'volsync/restore: schedule and manual are mutually exclusive — a restore either repeats on a cron (a warm standby) or runs once when its trigger name changes (a recovery)';
  {
    assert !std.objectHasAll(self, 'config') :
           'volsync/restore: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, storageClassName, moverSecurityContext), or the `restic` pass-through for anything else the mover accepts.",
    destination: {
      apiVersion: 'volsync.backube/v1alpha1',
      kind: 'ReplicationDestination',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        trigger: (
          if schedule != null then { schedule: schedule }
          else if manual != null then { manual: manual }
          else null
        ),
        restic: std.prune({
          repository: repository,
          copyMethod: copyMethod,
          capacity: capacity,
          destinationPVC: destinationPVC,
          accessModes: (if accessModes == [] then null else accessModes),
          storageClassName: storageClassName,
          volumeSnapshotClassName: volumeSnapshotClassName,
          cacheCapacity: cacheCapacity,
          // Which snapshot to restore. Unset means the most recent one, which is
          // what a recovery wants; `restoreAsOf` recovers the state at a moment
          // (an RFC-3339 timestamp), and `previous` counts back from there — the
          // pair that walks past a corruption that was itself backed up.
          restoreAsOf: restoreAsOf,
          previous: previous,
          // The cache and staging volumes outlive the mover pod otherwise, and a
          // restore that ran once leaves them behind for as long as the resource
          // exists.
          cleanupCachePVC: cleanupCachePVC,
          cleanupTempPVC: cleanupTempPVC,
          moverSecurityContext: moverSecurityContext,
        }) + restic,
      }),
    },
  }
