<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# k8up

Backs up every PersistentVolume in a namespace on a schedule, authored as
[K8up](https://k8up.io/) `Schedule` and `Restore` custom resources. restic
underneath, one resource per namespace — so a volume is protected the moment it
appears rather than when somebody remembers to declare it. A claim annotated
`k8up.io/backup: "false"` is left out.

**Prerequisite:** the K8up operator must be installed in the cluster.

kurly authors no Secret. The repository Secret holds the password that encrypts
the repository and the object-storage credentials; the catalog's `secretKeys`
names them.

## Compose

Both stages are a `function(params)` returning the CR; adapt and render with
`kurly.list`:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local schedule = import 'github.com/metio/kurly/workloads/k8up/schedule.libsonnet';

kurly.list(schedule(
  name='tenant',
  s3={ endpoint: 'https://s3.example.com', bucket: 'tenant-backups' },
  keepDaily=7,
  keepWeekly=4,
  keepMonthly=12,
))
```

Three runs are scheduled by default, and they are not decoration. The backup
copies the volumes; the **prune** is what makes the retention policy real, since
nothing is deleted without it; the **check** verifies the repository's own
integrity, which is how a repository that has rotted is noticed before a restore
finds out. Either of the latter two can be turned off deliberately by passing
`null`.

Any backend K8up accepts that kurly does not model — Azure, GCS, B2, Swift, rest
— goes through `backend`, which is merged last:

```jsonnet
schedule(backend={ azure: { container: 'backups', accountNameSecretRef: { name: 'azure', key: 'account' } } })
```

## Restoring

The restore is a workload of its own, because a backup nobody has restored is a
guess. A `Restore` runs once, when it is applied:

```jsonnet
local restore = import 'github.com/metio/kurly/workloads/k8up/restore.libsonnet';

kurly.list(restore(
  name='recover',
  claim='nextcloud',
  s3={ endpoint: 'https://s3.example.com', bucket: 'tenant-backups' },
))
```

Restoring into a claim puts the data back where the application expects it.
Passing `restoreTo` instead writes a tarball to object storage, which is what to
do when the question is what a backup contains rather than putting it back.
`runnable=false` stages the recovery: the manifest lands, a person reads it, and
flipping the flag is the deliberate act that starts it.

## Choosing between this and volsync

Both are restic and both are declarative. K8up is per-namespace, so coverage is
automatic and uniform; [volsync](../volsync/) is per-claim, so each volume
carries its own schedule and retention. Neither answer is better in general,
which is why both are here.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: k8up }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-k8up, namespace: k8up }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/k8up, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: k8up }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-k8up, namespace: k8up }
spec: { sourceRef: { kind: OCIRepository, name: kurly-k8up } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: k8up-restore, namespace: k8up }
spec:
  serviceAccountName: k8up-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local restore = import 'github.com/metio/kurly/workloads/k8up/restore.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(restore())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-k8up, importPath: github.com/metio/kurly/workloads/k8up }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: k8up-schedule, namespace: k8up }
spec:
  serviceAccountName: k8up-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local schedule = import 'github.com/metio/kurly/workloads/k8up/schedule.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(schedule())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-k8up, importPath: github.com/metio/kurly/workloads/k8up }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: k8up, namespace: k8up }
spec:
  serviceAccountName: k8up-deployer
  rollbackOnFailure: true
  stages:
    - name: restore
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: k8up-restore
    - name: schedule
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: k8up-schedule
```

<!-- END generated: jaas-deploy -->
