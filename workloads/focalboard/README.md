<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# focalboard

[Focalboard](https://github.com/mattermost/focalboard) — a self-hosted project-management
and kanban tool for boards, tasks and roadmaps, an open alternative to Trello/Notion/Asana.
A plain composable `kurly.http` workload on the official image; with the default SQLite
backend its database and uploaded files live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local focalboard = import 'github.com/metio/kurly/workloads/focalboard/server.libsonnet';
kurly.list(focalboard())
```

Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8000`.

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
metadata: { name: kurly, namespace: focalboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-focalboard, namespace: focalboard }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/focalboard, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: focalboard }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-focalboard, namespace: focalboard }
spec: { sourceRef: { kind: OCIRepository, name: kurly-focalboard } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: focalboard, namespace: focalboard }
spec:
  serviceAccountName: focalboard-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/focalboard/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-focalboard, importPath: github.com/metio/kurly/workloads/focalboard }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: focalboard, namespace: focalboard }
spec:
  serviceAccountName: focalboard-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: focalboard
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: focalboard }
```

<!-- END generated: jaas-deploy -->
