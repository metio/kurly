<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# answer

[Apache Answer](https://github.com/apache/answer) — a self-hosted Q&A platform for
building a community knowledge base, à la Stack Overflow. A plain composable
`kurly.http` workload on the official image: with the SQLite backend its data and
uploads live on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local answer = import 'github.com/metio/kurly/workloads/answer/server.libsonnet';

kurly.list(answer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `answer` | |
| `image` | `docker.io/apache/answer:v2.0.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | data and uploads (`/data`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Persistence

The SQLite database and uploads live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/). Configure an external PostgreSQL/MySQL through the
installer to scale past the single SQLite writer.

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
metadata: { name: kurly, namespace: answer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-answer, namespace: answer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/answer, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: answer }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-answer, namespace: answer }
spec: { sourceRef: { kind: OCIRepository, name: kurly-answer } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: answer, namespace: answer }
spec:
  serviceAccountName: answer-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/answer/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-answer, importPath: github.com/metio/kurly/workloads/answer }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: answer, namespace: answer }
spec:
  serviceAccountName: answer-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: answer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: answer }
```

<!-- END generated: jaas-deploy -->
