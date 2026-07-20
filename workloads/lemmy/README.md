<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lemmy

[Lemmy](https://join-lemmy.org) — a self-hosted, open-source link aggregator and forum for the
Fediverse, a Reddit alternative. It runs as **three workloads** — a `backend` (API + federation),
a `ui` (web frontend), and `pictrs` (image storage) — backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet';
local ui = import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet';
local pictrs = import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='lemmy-db', database='lemmy')).items,
  kurly.list(backend()).items,
  kurly.list(ui(externalHost='lemmy.example.com')).items,
  kurly.list(pictrs()).items,
]))
```

The **backend** reads its config (with the PostgreSQL connection and the pict-rs API key) from
`/config/config.hjson`, mounted from an **existing Secret** you provide (`lemmy-config`) — kurly
never mints key material. The **ui** is the user-facing stage on `:1234` and reaches the backend
by its Service name. **pictrs** serves images on `:8080` with them stored on a ReadWriteOnce
volume (one replica, recreated), authenticated by an API key from its own Secret.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: lemmy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lemmy, namespace: lemmy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lemmy, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lemmy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lemmy, namespace: lemmy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lemmy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lemmy-backend, namespace: lemmy }
spec:
  serviceAccountName: lemmy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backend = import 'github.com/metio/kurly/workloads/lemmy/backend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(backend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lemmy, importPath: github.com/metio/kurly/workloads/lemmy }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lemmy-pictrs, namespace: lemmy }
spec:
  serviceAccountName: lemmy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local pictrs = import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(pictrs())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lemmy, importPath: github.com/metio/kurly/workloads/lemmy }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lemmy-ui, namespace: lemmy }
spec:
  serviceAccountName: lemmy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local ui = import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(ui())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lemmy, importPath: github.com/metio/kurly/workloads/lemmy }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lemmy, namespace: lemmy }
spec:
  serviceAccountName: lemmy-deployer
  rollbackOnFailure: true
  stages:
    - name: backend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: lemmy-backend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lemmy-backend }
    - name: pictrs
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: lemmy-pictrs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lemmy-pictrs }
    - name: ui
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: lemmy-ui
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lemmy-ui }
```

<!-- END generated: jaas-deploy -->
