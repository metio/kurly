<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# baserow

[Baserow](https://baserow.io/) — an open-source, no-code database and Airtable
alternative. A plain composable `kurly.http` workload on the official **all-in-one**
image, which bundles the backend, the web frontend, Celery workers, and (by default)
an embedded PostgreSQL and Redis — everything in `/baserow/data` on a PersistentVolume,
so a single instance needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local baserow = import 'github.com/metio/kurly/workloads/baserow/server.libsonnet';

kurly.list(baserow(publicUrl='https://baserow.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `baserow` | |
| `image` | `docker.io/baserow/baserow:2.3.2` | the all-in-one image |
| `storageSize` / `storageClass` | `10Gi` / cluster default | everything (`/baserow/data`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `baserow-secrets` | Secret with `BASEROW_SECRET_KEY`, `BASEROW_JWT_SIGNING_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it. Point `DATABASE_*`
/ `REDIS_*` at external services (a [cnpg-cluster](../cnpg-cluster/) and
[valkey](../valkey/)) through `env` to scale past the embedded single instance.

## Security and persistence

The all-in-one image supervises multiple processes (including the embedded database)
and writes across the root filesystem, so this workload relaxes kurly's non-root and
read-only-rootfs defaults while keeping dropped capabilities and no privilege
escalation. Everything lives on a ReadWriteOnce volume, so this is **one replica,
recreated**.

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
metadata: { name: kurly, namespace: baserow }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-baserow, namespace: baserow }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/baserow, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: baserow }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-baserow, namespace: baserow }
spec: { sourceRef: { kind: OCIRepository, name: kurly-baserow } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: baserow, namespace: baserow }
spec:
  serviceAccountName: baserow-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/baserow/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-baserow, importPath: github.com/metio/kurly/workloads/baserow }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: baserow, namespace: baserow }
spec:
  serviceAccountName: baserow-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: baserow
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: baserow }
```

<!-- END generated: jaas-deploy -->
