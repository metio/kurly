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
| `image` | `docker.io/chrislusf/seaweedfs:4.39` | |
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

## The all-in-one shape

`weed server -s3` runs every SeaweedFS role in one process against one `-dir`,
which is the quick-start topology and the right one for a modest in-cluster S3.
Splitting the roles into dedicated master, volume, and filer tiers is a different
deployment — not more replicas of this one, since these roles do not scale by
replication — so it belongs in its own stage rather than a replica count here.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-seaweedfs, namespace: storage }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/seaweedfs
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-seaweedfs, namespace: storage }
spec: { sourceRef: { kind: OCIRepository, name: kurly-seaweedfs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seaweedfs, namespace: storage }
spec:
  serviceAccountName: seaweedfs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local seaweedfs = import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet';
      function(storageSize='50Gi')
        kurly.list(seaweedfs(storageSize=storageSize))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,           importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seaweedfs, importPath: github.com/metio/kurly/workloads/seaweedfs }
  tlas:
    - name: storageSize
      value: "50Gi"
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: seaweedfs, namespace: storage }
spec:
  serviceAccountName: seaweedfs-deployer
  stages:
    - name: seaweedfs
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seaweedfs
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: StatefulSet
            name: seaweedfs
```
