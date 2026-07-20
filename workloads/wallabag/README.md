<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wallabag

[wallabag](https://github.com/wallabag/wallabag) — a self-hosted read-it-later app
that saves clean, readable copies of web pages. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL, with its saved
images on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wallabag = import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='wallabag-db', database='wallabag')).items,
  kurly.list(wallabag(domain='https://read.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wallabag` | |
| `image` | `docker.io/wallabag/wallabag:2.6.14` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | saved images |
| `dbHost` / `dbName` / `dbUser` | `wallabag-db-rw` / `wallabag` / `wallabag` | the PostgreSQL database |
| `domain` | inferred | the public URL |
| `secretName` | `wallabag-secrets` | Secret with `SYMFONY__ENV__DATABASE_PASSWORD` and `SYMFONY__ENV__SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

wallabag reads its database coordinates from env (with the `SYMFONY__ENV__` prefix)
and the database password and app secret from a provided Secret via `envFrom`. kurly
authors **no Secret** — fill `wallabag-secrets` with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `wallabag-db`.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Saved images live on a ReadWriteOnce volume, so this is **one
replica, recreated**.

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
metadata: { name: kurly, namespace: wallabag }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wallabag, namespace: wallabag }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wallabag, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wallabag }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wallabag, namespace: wallabag }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wallabag } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wallabag, namespace: wallabag }
spec:
  serviceAccountName: wallabag-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wallabag, importPath: github.com/metio/kurly/workloads/wallabag }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wallabag, namespace: wallabag }
spec:
  serviceAccountName: wallabag-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: wallabag
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wallabag }
```

<!-- END generated: jaas-deploy -->
