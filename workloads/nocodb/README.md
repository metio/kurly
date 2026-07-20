<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nocodb

[NocoDB](https://github.com/nocodb/nocodb) — an open-source Airtable alternative that
turns any SQL database into a smart spreadsheet. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL for its metadata,
with attachments on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nocodb = import 'github.com/metio/kurly/workloads/nocodb/server.libsonnet';

kurly.list(nocodb(publicUrl='https://nocodb.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `nocodb` | |
| `image` | `docker.io/nocodb/nocodb:2026.07.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | attachments (`/usr/app/data`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `nocodb-secrets` | Secret with `NC_DB` and `NC_AUTH_JWT_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Database and secrets

NocoDB reads `NC_DB` (a connection string with the database password, point it at a
[cnpg-cluster](../cnpg-cluster/)) and `NC_AUTH_JWT_SECRET` from the environment. kurly
authors **no Secret** — provide `nocodb-secrets` holding both, pulled in via `envFrom`
(fill it with [`kurly.externalSecret`](../../main.libsonnet)).

## Persistence

Local attachments live on a ReadWriteOnce volume, so this is **one replica,
recreated**. Move attachments to S3 (the [seaweedfs](../seaweedfs/) workload) to scale
out.

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
metadata: { name: kurly, namespace: nocodb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-nocodb, namespace: nocodb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/nocodb, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: nocodb }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-nocodb, namespace: nocodb }
spec: { sourceRef: { kind: OCIRepository, name: kurly-nocodb } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: nocodb, namespace: nocodb }
spec:
  serviceAccountName: nocodb-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/nocodb/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-nocodb, importPath: github.com/metio/kurly/workloads/nocodb }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: nocodb, namespace: nocodb }
spec:
  serviceAccountName: nocodb-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: nocodb
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: nocodb }
```

<!-- END generated: jaas-deploy -->
