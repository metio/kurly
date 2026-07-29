// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// volsync/backup — copies a PersistentVolume's contents off the cluster on a
// schedule, as a VolSync `ReplicationSource` custom resource. Like cnpg-cluster,
// this authors the CR directly rather than composing a kurly base kind: the
// mover pods belong to the VolSync operator, which reconciles this resource into
// the restic jobs that read the volume and write to a repository. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local backup = import 'github.com/metio/kurly/workloads/volsync/backup.libsonnet';
//   kurly.list(backup(name='nextcloud', sourcePVC='nextcloud', repository='nextcloud-restic'))
//
// PREREQUISITE: the VolSync operator must be installed in the cluster, and the
// repository Secret must exist in this namespace (see secretKeys in the catalog
// — kurly authors no Secret).
//
// A backup nobody has restored is a guess, so the restore side is a workload of
// its own: volsync/restore.libsonnet, pointed at the same repository.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='backup',
  sourcePVC='data',
  repository='restic-repository',
  schedule='0 2 * * *',
  manual=null,
  copyMethod='Snapshot',
  retain={ daily: 7, weekly: 4, monthly: 6 },
  pruneIntervalDays=14,
  cacheCapacity=null,
  cacheStorageClassName=null,
  storageClassName=null,
  volumeSnapshotClassName=null,
  accessModes=[],
  moverSecurityContext=null,
  restic={},
  labels={},
  annotations={},
)
  // Snapshot reads a point-in-time copy, so the application keeps writing while
  // the mover reads and the backup is internally consistent. Direct reads the
  // live volume, which is the only option without a CSI snapshotter but copies a
  // moving target — fine for a volume nobody writes during the window, wrong for
  // a database's data directory. Clone sits between the two. Naming a method the
  // cluster cannot perform fails at reconcile time, hours later and silently, so
  // at least a typo fails here.
  assert std.member(['Snapshot', 'Clone', 'Direct', 'None'], copyMethod) :
         "volsync/backup: copyMethod must be one of Snapshot, Clone, Direct, None — got '" + copyMethod + "'";
  // VolSync takes exactly one trigger. Both means the operator picks, which is
  // not a decision to leave to chance in something that protects data.
  assert manual == null || schedule == null :
         'volsync/backup: schedule and manual are mutually exclusive — a source either runs on a cron or waits to be triggered by name';
  {
    // A kurly feature composed onto this workload cannot work, and the failure
    // is invisible: features contribute to a hidden `config` that a BASE KIND
    // reads when it computes its manifests, and this workload has no base — it
    // authors a custom resource whose pods belong to an operator. So
    // `backup() + kurly.podLabels({…})` renders cleanly, exit 0, and the labels
    // are simply gone.
    assert !std.objectHasAll(self, 'config') :
           'volsync/backup: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, storageClassName, moverSecurityContext), or the `restic` pass-through for anything else the mover accepts.",
    source: {
      apiVersion: 'volsync.backube/v1alpha1',
      kind: 'ReplicationSource',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        sourcePVC: sourcePVC,
        trigger: (
          if manual != null then { manual: manual }
          else if schedule != null then { schedule: schedule }
          else null
        ),
        // The mover's own schema, modelled only where every repository needs the
        // field and passed through everywhere else. `restic` is merged LAST, so
        // a consumer needing something kurly has not thought of — a mover
        // resource limit, a custom CA, an affinity for the mover pod — sets it
        // without waiting for kurly to think of it.
        restic: std.prune({
          repository: repository,
          copyMethod: copyMethod,
          // Retention is the whole point of a backup policy and the one field
          // nobody should have to look up: what is kept, for how long. VolSync
          // hands it to restic's forget, so the names are restic's.
          retain: (if retain == {} then null else retain),
          // Pruning rewrites the repository and is expensive, so it runs on its
          // own cadence rather than after every backup.
          pruneIntervalDays: pruneIntervalDays,
          // The mover caches restic metadata between runs; a large repository
          // needs a bigger cache than the default, and a slow one benefits from
          // a faster class.
          cacheCapacity: cacheCapacity,
          cacheStorageClassName: cacheStorageClassName,
          storageClassName: storageClassName,
          volumeSnapshotClassName: volumeSnapshotClassName,
          accessModes: (if accessModes == [] then null else accessModes),
          moverSecurityContext: moverSecurityContext,
        }) + restic,
      }),
    },
  }
