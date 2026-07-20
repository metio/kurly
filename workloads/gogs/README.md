<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gogs

[Gogs](https://gogs.io) — a painless, self-hosted Git service: a lightweight, fast Git
server with a clean web UI. A plain composable `kurly.http` workload on the official
image; with the default SQLite backend its repositories and data live on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gogs = import 'github.com/metio/kurly/workloads/gogs/server.libsonnet';
kurly.list(gogs())
```

Git-over-SSH uses `:22` — add a Service for it; HTTP(S) Git works without it. Data at
`/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.

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
metadata: { name: kurly, namespace: gogs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gogs, namespace: gogs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gogs, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gogs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gogs, namespace: gogs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gogs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gogs, namespace: gogs }
spec:
  serviceAccountName: gogs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gogs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gogs, importPath: github.com/metio/kurly/workloads/gogs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gogs, namespace: gogs }
spec:
  serviceAccountName: gogs-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: gogs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gogs }
```

<!-- END generated: jaas-deploy -->
