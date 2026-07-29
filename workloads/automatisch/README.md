<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# automatisch

[Automatisch](https://automatisch.io) — a self-hosted, open-source business-automation /
workflow tool, an open alternative to Zapier. Two stages on the official image, backed
by an external PostgreSQL and Redis: a **web server** and a **background worker** that
runs the flow executions the server enqueues onto Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/automatisch/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='automatisch-db', database='automatisch'),
  server(),
  worker(),
])
```

Both stages read the PostgreSQL/Redis connection and the `ENCRYPTION_KEY` /
`WEBHOOK_SECRET_KEY` / `APP_SECRET_KEY` from a shared Secret (`automatisch-secrets`) via
`envFrom` — kurly authors **no Secret**. The server serves on `:3000`; the worker has no
Service. Flow state lives in PostgreSQL and Redis, so both stages are **stateless**.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: automatisch }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-automatisch, namespace: automatisch }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/automatisch, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: automatisch }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-automatisch, namespace: automatisch }
spec: { sourceRef: { kind: OCIRepository, name: kurly-automatisch } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: automatisch-server, namespace: automatisch }
spec:
  serviceAccountName: automatisch-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/automatisch/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-automatisch, importPath: github.com/metio/kurly/workloads/automatisch }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: automatisch-worker, namespace: automatisch }
spec:
  serviceAccountName: automatisch-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-automatisch, importPath: github.com/metio/kurly/workloads/automatisch }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: automatisch, namespace: automatisch }
spec:
  serviceAccountName: automatisch-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: automatisch-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: automatisch-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: automatisch-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: automatisch-worker }
```

<!-- END generated: jaas-deploy -->
