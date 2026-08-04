// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// backup: get a workload's volumes off the cluster, composed onto it with `+`.
// Another separate axis, the same shape as expose, network and mesh:
//
//   VolSync:  kurly.backup.volsync(repository='app-restic')
//   K8up:     kurly.backup.k8up()      /  kurly.backup.exclude()
//
// THE TWO TOOLS DISAGREE ABOUT SCOPE, and the axis mirrors that rather than
// papering over it, because papering over it is how a volume ends up unprotected
// while the manifest says otherwise.
//
//   VolSync is PER CLAIM. A ReplicationSource names one sourcePVC, so a workload
//   composing it gets one source per volume it owns, named after that volume.
//
//   K8up is PER NAMESPACE. A Schedule backs up every claim it finds, so there is
//   nothing for a workload to opt INTO — it is already in. What a workload can
//   usefully say is that it should be LEFT OUT, which is `exclude()`, and the
//   Schedule itself stays a workload you deploy (workloads/k8up/schedule.libsonnet),
//   the way network.denyAll and mesh.strictNamespace are placed with kurly.list.
//
// kurly.backup.k8up() therefore writes the inclusion marker EXPLICITLY even
// though the default already includes the volume. A default is a thing nobody
// decided; an annotation saying `k8up.io/backup: "true"` is a decision somebody
// can read, and it survives the day the namespace default flips.
//
// NEITHER RESTORES. A backup nobody has restored is a guess, and restoring is an
// operation rather than a steady state — you run it once, at the worst possible
// moment, against a repository. So it stays a workload of its own
// (volsync/restore.libsonnet, k8up/restore.libsonnet) pointed at the same
// repository, and the deep-tier scenarios prove the round trip by destroying a
// volume and reading the file back.
{
  // A recipe claims the shared `backup` exclusion group, so a workload cannot be
  // handed two backup schemes that would each believe they own its volumes.
  //
  // The assert reads a knob only base.core sets, NOT the presence of `config`:
  // the mixin contributes `config` itself, so asking whether it exists answers
  // its own question.
  local backup(name) = {
    assert std.objectHasAll(self.config, 'name') :
           'kurly.backup recipes protect a workload — compose them onto a kurly kind (http, worker, …)',
    config+:: { exclusive+: { backup+: [name] } },
  },

  // volsync emits one ReplicationSource per volume the workload owns.
  //
  //   repository  the Secret holding the restic repository URL and password.
  //               Required, and kurly authors no Secret — see the catalog's
  //               secretKeys for what it must contain.
  //   schedule    cron for the backup trigger; null with manual= for a
  //               one-shot.
  //   retain      what restic keeps, in restic's own vocabulary
  //               ({ daily, weekly, monthly, ... }).
  //   copyMethod  'Direct' reads the live volume; 'Snapshot' takes a
  //               VolumeSnapshot first and needs a CSI driver with a
  //               VolumeSnapshotClass. Direct is the default because it works
  //               everywhere, and is honest for a volume nothing is writing to
  //               during the window — which is not most databases.
  //   restic      merged LAST into the mover's spec, so anything this vocabulary
  //               does not model is still reachable.
  volsync(
    repository,
    schedule='0 2 * * *',
    manual=null,
    retain={ daily: 7, weekly: 4, monthly: 6 },
    copyMethod='Direct',
    pruneIntervalDays=null,
    cacheCapacity=null,
    storageClassName=null,
    volumeSnapshotClassName=null,
    restic={},
  ):: backup('volsync') {
    config+:: {
      backup: {
        variant: 'volsync',
        repository: repository,
        schedule: schedule,
        manual: manual,
        retain: retain,
        copyMethod: copyMethod,
        pruneIntervalDays: pruneIntervalDays,
        cacheCapacity: cacheCapacity,
        storageClassName: storageClassName,
        volumeSnapshotClassName: volumeSnapshotClassName,
        restic: restic,
        claimAnnotations: {},
      },
    },
  },

  // k8up states, on every claim the workload owns, that the namespace Schedule
  // should include it. Emits no object of its own: the Schedule is a workload.
  k8up():: backup('k8up') {
    config+:: {
      backup: {
        variant: 'k8up',
        claimAnnotations: { 'k8up.io/backup': 'true' },
      },
    },
  },

  // exclude marks the workload's claims to be left out of a namespace-wide
  // scheme — for a volume that is a cache, a scratch area, or a copy of
  // something already backed up elsewhere. Putting those in the repository costs
  // storage and restore time and protects nothing.
  exclude():: backup('exclude') {
    config+:: {
      backup: {
        variant: 'exclude',
        claimAnnotations: { 'k8up.io/backup': 'false' },
      },
    },
  },
}
