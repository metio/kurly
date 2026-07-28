<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# overleaf

[Overleaf](https://github.com/overleaf/overleaf) — the Community Edition of the
collaborative LaTeX editor (formerly ShareLaTeX). A plain composable `kurly.http`
workload on the official monolith image, backed by an external MongoDB and Redis,
with its user projects and compiles on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local overleaf = import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  valkey(name='overleaf-cache'),
  overleaf(siteUrl='https://latex.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `overleaf` | |
| `image` | `docker.io/sharelatex/sharelatex:6.2.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | projects and compiles (`/var/lib/overleaf`) |
| `redisHost` | `overleaf-cache` | the Redis/valkey Service |
| `siteUrl` | inferred | the public URL |
| `appName` | `Overleaf` | the instance name |
| `secretName` | `overleaf-secrets` | Secret with `OVERLEAF_MONGO_URL` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Databases and secrets

Overleaf needs **MongoDB** (a **replica set** — it uses transactions) and **Redis**.
kurly ships no MongoDB recipe — bring your own; Redis can be the
[valkey](../valkey/) workload. It reads `OVERLEAF_REDIS_HOST` and its site config
from env, and `OVERLEAF_MONGO_URL` (with any credentials) from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `overleaf-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The image spawns TeX compile processes and writes across the root filesystem, so
this workload relaxes kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation. User projects and compiles live on
a ReadWriteOnce volume, so this is **one replica, recreated**.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: overleaf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-overleaf, namespace: overleaf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/overleaf, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: overleaf }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-overleaf, namespace: overleaf }
spec: { sourceRef: { kind: OCIRepository, name: kurly-overleaf } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: overleaf, namespace: overleaf }
spec:
  serviceAccountName: overleaf-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-overleaf, importPath: github.com/metio/kurly/workloads/overleaf }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: overleaf, namespace: overleaf }
spec:
  serviceAccountName: overleaf-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: overleaf
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: overleaf }
```

<!-- END generated: jaas-deploy -->
