<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bugsink

[Bugsink](https://www.bugsink.com/) — a self-hosted, Sentry-compatible error tracker:
it ingests the same events your existing Sentry SDKs already emit. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL or MySQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bugsink = import 'github.com/metio/kurly/workloads/bugsink/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='bugsink-db', database='bugsink'),
  bugsink(baseUrl='https://errors.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bugsink` | |
| `image` | `docker.io/bugsink/bugsink:2.4.0` | |
| `replicas` | `2` | stateless — scale freely |
| `baseUrl` | inferred | the public URL (validated Host header) |
| `behindHttps` | `true` | secure-cookie / HTTPS handling |
| `secretName` | `bugsink-secrets` | Secret with `DATABASE_URL` and `SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and the event-ingestion API on `:8000` — compose an exposure onto it.

## Database and secrets

Bugsink reads `DATABASE_URL` and `SECRET_KEY` from the environment. kurly authors **no
Secret** — provide `bugsink-secrets` holding both, pulled in via `envFrom` (fill it
with [`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `bugsink-db`.

## Persistence

Backed by an external database, events live in the DB, so this is **stateless** — a
plain rolling Deployment with no volume.

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
metadata: { name: kurly, namespace: bugsink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bugsink, namespace: bugsink }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bugsink, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bugsink }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bugsink, namespace: bugsink }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bugsink } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bugsink, namespace: bugsink }
spec:
  serviceAccountName: bugsink-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bugsink/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bugsink, importPath: github.com/metio/kurly/workloads/bugsink }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bugsink, namespace: bugsink }
spec:
  serviceAccountName: bugsink-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: bugsink
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bugsink }
```

<!-- END generated: jaas-deploy -->
