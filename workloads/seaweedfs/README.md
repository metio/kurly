<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# seaweedfs

[SeaweedFS](https://github.com/seaweedfs/seaweedfs) as an **all-in-one object
store** — the `kurly.stateful` shape, a StatefulSet with a per-pod PVC and a
headless Service, running `weed server -s3` so one process is master + volume +
filer + an **S3 gateway**. It gives a cluster an S3 API (port `8333`) backed by a
PersistentVolume — an in-cluster target for anything that speaks S3, including a
[cnpg-cluster](../cnpg-cluster/)'s WAL and base backups.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local seaweedfs = import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet';

kurly.list(seaweedfs(storageSize='50Gi', storageClass='fast'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `seaweedfs` | also names the headless Service |
| `image` | `docker.io/chrislusf/seaweedfs:4.40` | |
| `storageSize` | `10Gi` | the data volume, mounted at `/data` |
| `storageClass` | cluster default | |

## Reaching the S3 API

Clients reach the gateway at `<name>-0.<name>-headless.<namespace>.svc:8333`.
The default configuration serves anonymous access, which is fine inside a trusted
namespace; put credentials in front of it (a SeaweedFS `identities` config) before
exposing it more widely.

## Backing up a cnpg-cluster to it

This is why it pairs with the PostgreSQL workload: a `cnpg-cluster` writes its
backups to S3, and this gives that S3 a home in the same cluster. Point the
cluster's backup at the gateway and wire the IAM the operator's ServiceAccount
carries (`cnpg-cluster(serviceAccountAnnotations=…)`), or a static credentials
Secret, to authenticate.

## The all-in-one shape, or the split

`server` runs every SeaweedFS role in one process against one `-dir` — the
quick-start topology, and the right one for a modest in-cluster S3.

For a store that grows, the roles split into three stages you deploy together —
each a normal `kurly.stateful` workload, so every kurly feature composes onto it:

| Stage | Role | Scale by |
|---|---|---|
| `master` | coordinates topology, assigns file IDs | (usually one) |
| `volume` | stores the file data | **replicas** — each a pod with its own PVC |
| `filer` | filesystem + S3 gateway over the volumes | replicas |

The volume and filer stages take the master's address, so the wiring is explicit:

```jsonnet
local master = import 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet';
local volume = import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet';
local filer  = import 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet';

local endpoint = 'seaweedfs-master-0.seaweedfs-master-headless:9333';  // the default
kurly.list(master())
kurly.list(volume(replicas=3, storageSize='100Gi', masterEndpoint=endpoint))
kurly.list(filer(masterEndpoint=endpoint))
```

Clients reach the S3 gateway at `seaweedfs-filer-0.seaweedfs-filer-headless:8333`.
Each volume server advertises its **pod IP** to the master (through the downward
API) so a read is handed a routable address rather than an unresolvable short
hostname — the one thing a split SeaweedFS on Kubernetes must get right.

Capacity is the split's whole point: the all-in-one has a single data process, so
scaling it means a bigger volume; the split scales the volume tier out by adding
servers. That is why these are separate stages, not a replica count on `server`.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: seaweedfs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-seaweedfs, namespace: seaweedfs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/seaweedfs, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: seaweedfs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-seaweedfs, namespace: seaweedfs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-seaweedfs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seaweedfs-filer, namespace: seaweedfs }
spec:
  serviceAccountName: seaweedfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local filer = import 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(filer())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seaweedfs, importPath: github.com/metio/kurly/workloads/seaweedfs }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seaweedfs-master, namespace: seaweedfs }
spec:
  serviceAccountName: seaweedfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local master = import 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(master())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seaweedfs, importPath: github.com/metio/kurly/workloads/seaweedfs }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seaweedfs-server, namespace: seaweedfs }
spec:
  serviceAccountName: seaweedfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seaweedfs, importPath: github.com/metio/kurly/workloads/seaweedfs }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seaweedfs-volume, namespace: seaweedfs }
spec:
  serviceAccountName: seaweedfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local volume = import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(volume())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seaweedfs, importPath: github.com/metio/kurly/workloads/seaweedfs }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: seaweedfs, namespace: seaweedfs }
spec:
  serviceAccountName: seaweedfs-deployer
  rollbackOnFailure: true
  stages:
    - name: filer
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seaweedfs-filer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: seaweedfs-filer }
    - name: master
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seaweedfs-master
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: seaweedfs-master }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seaweedfs-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: seaweedfs-server }
    - name: volume
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seaweedfs-volume
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: StatefulSet, name: seaweedfs-volume }
```

<!-- END generated: jaas-deploy -->
