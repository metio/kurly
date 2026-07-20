<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mattermost

[Mattermost](https://mattermost.com) — a self-hosted, open-source team messaging
platform: channels, threads, and integrations, à la Slack. A plain composable
`kurly.http` workload on the Team Edition image, backed by an external PostgreSQL, with
its file uploads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mattermost = import 'github.com/metio/kurly/workloads/mattermost/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='mattermost-db', database='mattermost')).items,
  kurly.list(mattermost(siteUrl='https://chat.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mattermost` | |
| `image` | `docker.io/mattermost/mattermost-team-edition:11.8.4` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | uploads (`/mattermost/data`) |
| `siteUrl` | inferred | the public URL |
| `secretName` | `mattermost-secrets` | Secret with `MM_SQLSETTINGS_DATASOURCE` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:8065` — compose an exposure onto it.

## Persistence

Uploaded files live on a ReadWriteOnce volume, so this is **one replica, recreated**.
Point the file store at S3 (`MM_FILESETTINGS_DRIVERNAME=amazons3`) to run more than one
replica.

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
metadata: { name: kurly, namespace: mattermost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mattermost, namespace: mattermost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mattermost, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mattermost }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mattermost, namespace: mattermost }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mattermost } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mattermost, namespace: mattermost }
spec:
  serviceAccountName: mattermost-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mattermost/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mattermost, importPath: github.com/metio/kurly/workloads/mattermost }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mattermost, namespace: mattermost }
spec:
  serviceAccountName: mattermost-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mattermost
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mattermost }
```

<!-- END generated: jaas-deploy -->
