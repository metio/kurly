<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# n8n

[n8n](https://github.com/n8n-io/n8n) — a fair-code workflow-automation tool: connect
apps and automate tasks with a visual editor. A plain composable `kurly.http`
workload that keeps its workflows, credentials, and encryption key in a SQLite
database on a PersistentVolume by default, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local n8n = import 'github.com/metio/kurly/workloads/n8n/server.libsonnet';

kurly.list(n8n(host='n8n.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `n8n` | |
| `image` | `docker.io/n8nio/n8n:2.31.4` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/home/node/.n8n`) |
| `host` | inferred | the public hostname (webhooks need it) |
| `env` | `{}` | extra `N8N_*` / `DB_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the editor, API, and webhooks on `:5678` — compose an exposure onto it.

## Persistence

The SQLite database and the auto-generated encryption key live on a ReadWriteOnce
volume, so this is **one replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/). Point `DB_TYPE` at an external PostgreSQL and set
`N8N_ENCRYPTION_KEY` (from a Secret, via `env`) to scale out.

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
metadata: { name: kurly, namespace: n8n }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-n8n, namespace: n8n }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/n8n, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: n8n }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-n8n, namespace: n8n }
spec: { sourceRef: { kind: OCIRepository, name: kurly-n8n } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: n8n, namespace: n8n }
spec:
  serviceAccountName: n8n-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/n8n/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-n8n, importPath: github.com/metio/kurly/workloads/n8n }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: n8n, namespace: n8n }
spec:
  serviceAccountName: n8n-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: n8n
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: n8n }
```

<!-- END generated: jaas-deploy -->
