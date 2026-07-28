<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vikunja

[Vikunja](https://vikunja.io/) — a self-hosted to-do and project-management app. A
plain composable `kurly.http` workload on the official all-in-one image: it keeps its
data in a SQLite database and its file attachments on a PersistentVolume by default,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vikunja = import 'github.com/metio/kurly/workloads/vikunja/server.libsonnet';

kurly.list(vikunja(publicUrl='https://tasks.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vikunja` | |
| `image` | `docker.io/vikunja/vikunja:v2.4.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | database (`/db`) and attachments (`/files`) |
| `publicUrl` | inferred | the public URL |
| `secretName` | `vikunja-secrets` | Secret with `VIKUNJA_SERVICE_JWTSECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3456` — compose an exposure onto it. Point
`VIKUNJA_DATABASE_TYPE` at an external PostgreSQL/MySQL through `env` to scale past the
single SQLite writer.

## Secrets and persistence

Vikunja reads `VIKUNJA_SERVICE_JWTSECRET` from the environment (keep it stable —
sessions depend on it). kurly authors **no Secret** — provide `vikunja-secrets`
holding it, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The SQLite database and attachments
live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: vikunja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vikunja, namespace: vikunja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vikunja, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vikunja }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vikunja, namespace: vikunja }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vikunja } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vikunja, namespace: vikunja }
spec:
  serviceAccountName: vikunja-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vikunja/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vikunja, importPath: github.com/metio/kurly/workloads/vikunja }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vikunja, namespace: vikunja }
spec:
  serviceAccountName: vikunja-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: vikunja
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vikunja }
```

<!-- END generated: jaas-deploy -->
