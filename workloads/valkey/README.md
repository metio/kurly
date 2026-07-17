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

  Clients connect to the **`valkey`** Service, which follows the current primary:
  a sidecar labels its own pod `kurly.dev/valkey-role=primary` while it is the
  master (removing the label on a replica), and the Service selects that label —
  so the Service is **never routed to a replica**. When the master role migrates
  during a hand-off, the label follows the promoted pod within about a second; the
  demoted master leaves the Service as it terminates, so at the failover instant
  there is a brief moment with no endpoint — clients reconnect (never reaching a
  replica), exactly as they would across any single-master failover.
  (`valkey-headless` remains for peer discovery.)

  The labeler is a Kubernetes API client, so it carries a namespaced Role with
  `get` and `patch` on pods (nothing else) and needs egress to the apiserver. It declares
  both through `kurly.apiServerClient`, so composing your own `kurly.rbac(...)` or
  `kurly.networkPolicy(...)` onto the cache **adds to** the grant rather than
  replacing it — a NetworkPolicy cannot accidentally firewall off the labeler. On
  vanilla NetworkPolicy the apiserver egress is a best-effort TCP 443/6443 allow
  (the API has no way to name the apiserver); on Calico or Cilium you can tighten
  it to the apiserver entity.

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
| `image` | `docker.io/valkey/valkey:9.0.3` | any Redis-compatible server built the same way |
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
    - name: storageSize
      value: "5Gi"
    - name: maxMemory
      value: 512mb
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
