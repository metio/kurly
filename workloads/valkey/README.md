<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# valkey

A persistent [Valkey](https://valkey.io/) server (the BSD, Linux-Foundation
Redis fork; API-compatible with Redis) on the **official upstream image** — kurly
ships no customized build. This is the single-instance stage, composed on
`kurly.stateful`: a StatefulSet with a per-pod PVC and the headless Service that
names it. A primary+replica stage and a cluster-mode stage will slot in beside
it; a Redis-compatible alternative (KeyDB, Dragonfly, …) runs by overriding
`image`.

Clients reach it at `<pod>.valkey-headless.<namespace>.svc` on port `6379`.

## Variants

- **`instance.libsonnet`** — the persistent single instance above (durable store).
- **`cache.libsonnet`** — an in-memory cache that **upgrades its version with zero
  downtime and no data loss**, on the stock image and with **no orchestrator**.
  The replication hand-off lives entirely in the pod manifests: a headless
  Service for peer discovery, a `maxSurge: 1` RollingUpdate so the new pod
  overlaps the old, an initContainer that finds the running peer and boots as its
  replica, a readiness gate on `master_link_status:up`, and a `preStop` that runs
  Valkey's own atomic `failover` before the old pod exits. A plain `kubectl
  apply`, a Helm upgrade, or a stageset roll all trigger it identically.

  ```jsonnet
  local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';
  kurly.list(valkey(maxMemory='512mb'))
  ```

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';

kurly.list(valkey(storageSize='5Gi', maxMemory='512mb'))
```

| Parameter | Default | Notes |
|---|---|---|
| `image` | `docker.io/valkey/valkey:8` | any Redis-compatible server built the same way |
| `storageSize` | `1Gi` | the per-pod volume for append-only persistence |
| `storageClass` | cluster default | |
| `maxMemory` | — | e.g. `512mb`; caps the dataset with `allkeys-lru` eviction. Unset grows to the pod memory limit. |

The container runs as the image's non-root `valkey` user (uid 999); the pod's
fsGroup matches so it owns the volume, and the rest of kurly's restricted posture
(read-only root filesystem, dropped capabilities, seccomp) applies unchanged.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: valkey }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-valkey, namespace: valkey }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/valkey, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: valkey }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-valkey, namespace: valkey }
spec: { sourceRef: { kind: OCIRepository, name: kurly-valkey } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: valkey, namespace: valkey }
spec:
  serviceAccountName: valkey-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';
      function(storageSize='5Gi', maxMemory='512mb')
        kurly.list(valkey(storageSize=storageSize, maxMemory=maxMemory))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,         importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-valkey,  importPath: github.com/metio/kurly/workloads/valkey }
  tlas:
    storageSize: ["5Gi"]
    maxMemory: ["512mb"]
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: valkey, namespace: valkey }
spec:
  serviceAccountName: valkey-deployer
  rollbackOnFailure: true
  stages:
    - name: instance
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: valkey
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: StatefulSet
            name: valkey
```
