<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# baikal

[Baïkal](https://github.com/sabre-io/Baikal) — a lightweight CalDAV + CardDAV
server built on [sabre/dav](https://sabre.io/). A plain composable `kurly.http`
workload on the maintained [ckulka](https://github.com/ckulka/baikal-docker) image
that keeps its configuration and SQLite database on a PersistentVolume, so it needs
no external database by default.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local baikal = import 'github.com/metio/kurly/workloads/baikal/server.libsonnet';

kurly.list(baikal())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `baikal` | |
| `image` | `docker.io/ckulka/baikal:0.10.1-nginx` | the nginx variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (DB at `/Specific`, config at `/config`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the admin UI and CalDAV/CardDAV on `:80` — compose an exposure onto it:

```jsonnet
kurly.list([
  baikal()
  + kurly.expose.ownGateway('dav.example.com', 'istio', tls='baikal-tls'),
  kurly.certificate('baikal-tls', ['dav.example.com'], 'letsencrypt-prod'),
])
```

Point Baïkal at an external MySQL/PostgreSQL through its setup wizard to scale past
the single SQLite writer.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Both the database and the generated
config live on one ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: baikal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-baikal, namespace: baikal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/baikal, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: baikal }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-baikal, namespace: baikal }
spec: { sourceRef: { kind: OCIRepository, name: kurly-baikal } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: baikal, namespace: baikal }
spec:
  serviceAccountName: baikal-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/baikal/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-baikal, importPath: github.com/metio/kurly/workloads/baikal }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: baikal, namespace: baikal }
spec:
  serviceAccountName: baikal-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: baikal
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: baikal }
```

<!-- END generated: jaas-deploy -->
