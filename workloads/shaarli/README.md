<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shaarli

[Shaarli](https://github.com/shaarli/Shaarli) — a self-hosted, database-free bookmarking
and link-sharing app: a personal, minimalist "delicious" you fully own. A plain composable
`kurly.http` workload on the official image; because Shaarli is flat-file, its data lives
on a PersistentVolume — no external database.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shaarli = import 'github.com/metio/kurly/workloads/shaarli/server.libsonnet';
kurly.list(shaarli())
```

Data at `/var/www/shaarli/data` on a ReadWriteOnce volume, so **one replica, recreated**.
Serves on `:80`.

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
metadata: { name: kurly, namespace: shaarli }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-shaarli, namespace: shaarli }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/shaarli, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: shaarli }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-shaarli, namespace: shaarli }
spec: { sourceRef: { kind: OCIRepository, name: kurly-shaarli } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: shaarli, namespace: shaarli }
spec:
  serviceAccountName: shaarli-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/shaarli/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-shaarli, importPath: github.com/metio/kurly/workloads/shaarli }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: shaarli, namespace: shaarli }
spec:
  serviceAccountName: shaarli-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: shaarli
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: shaarli }
```

<!-- END generated: jaas-deploy -->
