<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pocketbase

[PocketBase](https://pocketbase.io) — a self-hosted, open-source backend in one file: an embedded SQLite database, auth, file storage and a REST/realtime API, with an admin dashboard. A `kurly.http` workload; database, uploads and migrations on a PersistentVolume under `/pb_data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pocketbase = import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet';
kurly.list(pocketbase())
```

Data at `/pb_data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the API and admin UI on `:8080`. On first run, create the superuser via the admin UI or the CLI.

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
metadata: { name: kurly, namespace: pocketbase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pocketbase, namespace: pocketbase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pocketbase, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pocketbase }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pocketbase, namespace: pocketbase }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pocketbase } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pocketbase, namespace: pocketbase }
spec:
  serviceAccountName: pocketbase-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pocketbase, importPath: github.com/metio/kurly/workloads/pocketbase }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pocketbase, namespace: pocketbase }
spec:
  serviceAccountName: pocketbase-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: pocketbase
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pocketbase }
```

<!-- END generated: jaas-deploy -->
