<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# blinko

[Blinko](https://github.com/blinko-space/blinko) — a self-hosted, AI-powered
note-taking app for quickly capturing ideas. A plain composable `kurly.http` workload
on the official image, backed by an external PostgreSQL, with its uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local blinko = import 'github.com/metio/kurly/workloads/blinko/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='blinko-db', database='blinko')).items,
  kurly.list(blinko(nextauthUrl='https://notes.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `blinko` | |
| `image` | `docker.io/blinkospace/blinko:1.8.8` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads (`/app/.blinko`) |
| `nextauthUrl` | inferred | the public URL |
| `secretName` | `blinko-secrets` | Secret with `DATABASE_URL` and `NEXTAUTH_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:1111` — compose an exposure onto it.

## Database and secrets

Blinko reads `DATABASE_URL` (with the database password embedded) and `NEXTAUTH_SECRET`
from the environment. kurly authors **no Secret** — provide `blinko-secrets` holding
both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `blinko-db`.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: blinko }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-blinko, namespace: blinko }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/blinko, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: blinko }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-blinko, namespace: blinko }
spec: { sourceRef: { kind: OCIRepository, name: kurly-blinko } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: blinko, namespace: blinko }
spec:
  serviceAccountName: blinko-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/blinko/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-blinko, importPath: github.com/metio/kurly/workloads/blinko }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: blinko, namespace: blinko }
spec:
  serviceAccountName: blinko-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: blinko
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: blinko }
```

<!-- END generated: jaas-deploy -->
