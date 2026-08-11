<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# volsync

Copies a PersistentVolume's contents off the cluster and back, authored as
[VolSync](https://volsync.readthedocs.io/) `ReplicationSource` and
`ReplicationDestination` custom resources. restic underneath, one resource per
claim — so a volume states its own backup policy next to itself, and two
volumes in a namespace can be kept for different lengths of time.

**Prerequisites:** the VolSync operator must be installed in the cluster, and
the default `Snapshot` copy method needs a CSI driver with a
`VolumeSnapshotClass`. `Direct` works without one but copies the live volume —
fine where nothing writes during the window, wrong for a database's data
directory.

kurly authors no Secret. The repository Secret holds `RESTIC_REPOSITORY`,
`RESTIC_PASSWORD` and the object-storage credentials; the catalog's `secretKeys`
names them.

## Compose

Both stages are a `function(params)` returning the CR; adapt and render with
`kurly.list`:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backup = import 'github.com/metio/kurly/workloads/volsync/backup.libsonnet';

kurly.list(backup(
  name='nextcloud',
  sourcePVC='nextcloud',
  repository='nextcloud-restic',
  schedule='0 2 * * *',
  retain={ daily: 7, weekly: 4, monthly: 12 },
))
```

Anything the restic mover accepts that kurly does not model — a resource limit
for the mover pod, a custom CA, a node selector — goes through `restic`, which
is merged last:

```jsonnet
backup(
  sourcePVC='nextcloud',
  repository='nextcloud-restic',
  restic={ unlock: 'force', moverResources: { limits: { memory: '2Gi' } } },
)
```

## Restoring

The restore is a workload of its own, because a backup nobody has restored is a
guess. It runs once, when the `manual` trigger's name changes, and by default
restores the most recent snapshot into a volume VolSync provisions:

```jsonnet
local restore = import 'github.com/metio/kurly/workloads/volsync/restore.libsonnet';

kurly.list(restore(
  name='nextcloud',
  repository='nextcloud-restic',
  capacity='20Gi',
))
```

`restoreAsOf` recovers the state at a moment and `previous` counts back from
there — the pair that walks past a corruption which was itself backed up.

## Choosing between this and k8up

Both are restic and both are declarative. VolSync is per-claim, so each volume
carries its own schedule and retention; [k8up](../k8up/) is per-namespace, so a
new volume is protected the moment it appears rather than when somebody
remembers to declare it. Neither answer is better in general, which is why both
are here.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: volsync }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-volsync, namespace: volsync }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/volsync, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: volsync }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-volsync, namespace: volsync }
spec: { sourceRef: { kind: OCIRepository, name: kurly-volsync } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: volsync-backup, namespace: volsync }
spec:
  serviceAccountName: volsync-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backup = import 'github.com/metio/kurly/workloads/volsync/backup.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(backup())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-volsync, importPath: github.com/metio/kurly/workloads/volsync }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: volsync-restore, namespace: volsync }
spec:
  serviceAccountName: volsync-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local restore = import 'github.com/metio/kurly/workloads/volsync/restore.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(restore())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-volsync, importPath: github.com/metio/kurly/workloads/volsync }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: volsync, namespace: volsync }
spec:
  serviceAccountName: volsync-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: backup
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: volsync-backup
    - name: restore
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: volsync-restore
```

<!-- END generated: jaas-deploy -->
