<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# changedetection

[changedetection.io](https://changedetection.io) — self-hosted website change detection:
watch pages and get notified when they change, with optional visual-diff and price
tracking. A plain composable `kurly.http` workload on the official image; its datastore
(SQLite plus page snapshots) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local changedetection = import 'github.com/metio/kurly/workloads/changedetection/server.libsonnet';
kurly.list(changedetection(baseUrl='https://watch.example.com'))
```

Fetching JavaScript pages needs a companion Playwright/Chrome service
(`PLAYWRIGHT_DRIVER_URL`); the plain HTTP fetcher works without it. Datastore at
`/datastore` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5000`.

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
metadata: { name: kurly, namespace: changedetection }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-changedetection, namespace: changedetection }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/changedetection, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: changedetection }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-changedetection, namespace: changedetection }
spec: { sourceRef: { kind: OCIRepository, name: kurly-changedetection } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: changedetection, namespace: changedetection }
spec:
  serviceAccountName: changedetection-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/changedetection/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-changedetection, importPath: github.com/metio/kurly/workloads/changedetection }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: changedetection, namespace: changedetection }
spec:
  serviceAccountName: changedetection-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: changedetection
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: changedetection }
```

<!-- END generated: jaas-deploy -->
