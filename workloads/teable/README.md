<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# teable

[Teable](https://teable.io) — a self-hosted, no-code database built on PostgreSQL that presents as a spreadsheet, an Airtable alternative. A `kurly.http` workload on the official image, backed by an external PostgreSQL (and Redis for realtime/caching).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local teable = import 'github.com/metio/kurly/workloads/teable/server.libsonnet';
kurly.list(teable(publicOrigin='https://teable.example.com'))
```

Stateless with S3 attachment storage — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Teable reads `PRISMA_DATABASE_URL`, `BACKEND_CACHE_REDIS_URI`, `SECRET_KEY` and its mail/storage settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `teable-db` and a Redis.

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
metadata: { name: kurly, namespace: teable }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-teable, namespace: teable }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/teable, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: teable }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-teable, namespace: teable }
spec: { sourceRef: { kind: OCIRepository, name: kurly-teable } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: teable, namespace: teable }
spec:
  serviceAccountName: teable-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/teable/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-teable, importPath: github.com/metio/kurly/workloads/teable }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: teable, namespace: teable }
spec:
  serviceAccountName: teable-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: teable
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: teable }
```

<!-- END generated: jaas-deploy -->
