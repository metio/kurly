<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hedgedoc

[HedgeDoc](https://github.com/hedgedoc/hedgedoc) — real-time, collaborative markdown
notes. A plain composable `kurly.http` workload on the official image, backed by an
external PostgreSQL, with its uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hedgedoc = import 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='hedgedoc-db', database='hedgedoc')).items,
  kurly.list(hedgedoc(domain='pad.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `hedgedoc` | |
| `image` | `quay.io/hedgedoc/hedgedoc:1.11.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded files |
| `domain` | inferred | the public domain |
| `secretName` | `hedgedoc-secrets` | Secret with `CMD_DB_URL` and `CMD_SESSION_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

HedgeDoc reads `CMD_DB_URL` (with the database password embedded) and
`CMD_SESSION_SECRET` from the environment. kurly authors **no Secret** — provide
`hedgedoc-secrets` holding both, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `hedgedoc-db`.

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
metadata: { name: kurly, namespace: hedgedoc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hedgedoc, namespace: hedgedoc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hedgedoc, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hedgedoc }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hedgedoc, namespace: hedgedoc }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hedgedoc } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hedgedoc, namespace: hedgedoc }
spec:
  serviceAccountName: hedgedoc-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hedgedoc, importPath: github.com/metio/kurly/workloads/hedgedoc }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hedgedoc, namespace: hedgedoc }
spec:
  serviceAccountName: hedgedoc-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: hedgedoc
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hedgedoc }
```

<!-- END generated: jaas-deploy -->
