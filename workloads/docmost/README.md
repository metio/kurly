<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docmost

[Docmost](https://github.com/docmost/docmost) — a self-hosted, open-source
collaborative wiki and documentation platform. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL and Redis, with its
attachments on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local docmost = import 'github.com/metio/kurly/workloads/docmost/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='docmost-db', database='docmost')).items,
  kurly.list(docmost(appUrl='https://wiki.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `docmost` | |
| `image` | `docker.io/docmost/docmost:0.95.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | attachments (`/app/data/storage`) |
| `appUrl` | inferred | the public URL |
| `secretName` | `docmost-secrets` | Secret with `DATABASE_URL`, `REDIS_URL`, `APP_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Backends and secrets

Docmost reads `DATABASE_URL`, `REDIS_URL` and `APP_SECRET` from the environment. kurly
authors **no Secret** — provide `docmost-secrets` holding all three, pulled in via
`envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)). The defaults
pair with a [cnpg-cluster](../cnpg-cluster/) named `docmost-db` and a Redis.

## Persistence

Local attachment storage lives on a ReadWriteOnce volume, so this is **one replica,
recreated**. Point `STORAGE_DRIVER` at S3 to scale past the single writer.

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
metadata: { name: kurly, namespace: docmost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-docmost, namespace: docmost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/docmost, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: docmost }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-docmost, namespace: docmost }
spec: { sourceRef: { kind: OCIRepository, name: kurly-docmost } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docmost, namespace: docmost }
spec:
  serviceAccountName: docmost-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/docmost/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docmost, importPath: github.com/metio/kurly/workloads/docmost }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: docmost, namespace: docmost }
spec:
  serviceAccountName: docmost-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docmost
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docmost }
```

<!-- END generated: jaas-deploy -->
