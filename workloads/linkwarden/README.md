<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# linkwarden

[Linkwarden](https://github.com/linkwarden/linkwarden) — a self-hosted bookmark
manager that archives a copy of every page. A plain composable `kurly.http` workload
on the official image, backed by an external PostgreSQL, with its archived pages on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local linkwarden = import 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='linkwarden-db', database='linkwarden')).items,
  kurly.list(linkwarden(nextauthUrl='https://links.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `linkwarden` | |
| `image` | `ghcr.io/linkwarden/linkwarden:v2.15.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | archived pages (`/data/data`) |
| `nextauthUrl` | inferred | the public URL |
| `secretName` | `linkwarden-secrets` | Secret with `DATABASE_URL` and `NEXTAUTH_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Linkwarden reads `DATABASE_URL` (with the database password embedded) and
`NEXTAUTH_SECRET` from the environment. kurly authors **no Secret** — provide
`linkwarden-secrets` holding both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `linkwarden-db`.

## Persistence

With local storage, archived pages live on a ReadWriteOnce volume, so this is **one
replica, recreated**. Move storage to S3 (the [seaweedfs](../seaweedfs/) workload) to
scale out.

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
metadata: { name: kurly, namespace: linkwarden }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-linkwarden, namespace: linkwarden }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/linkwarden, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: linkwarden }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-linkwarden, namespace: linkwarden }
spec: { sourceRef: { kind: OCIRepository, name: kurly-linkwarden } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: linkwarden, namespace: linkwarden }
spec:
  serviceAccountName: linkwarden-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-linkwarden, importPath: github.com/metio/kurly/workloads/linkwarden }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: linkwarden, namespace: linkwarden }
spec:
  serviceAccountName: linkwarden-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: linkwarden
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: linkwarden }
```

<!-- END generated: jaas-deploy -->
