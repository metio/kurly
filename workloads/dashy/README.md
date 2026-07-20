<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dashy

[Dashy](https://github.com/Lissy93/dashy) — a highly customizable, self-hosted
dashboard for your services. A plain composable `kurly.http` workload on the
official image; its configuration lives on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dashy = import 'github.com/metio/kurly/workloads/dashy/server.libsonnet';

kurly.list(dashy())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dashy` | |
| `image` | `docker.io/lissy93/dashy:4.4.7` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration (`/app/user-data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:8080` — compose an exposure onto it. Edit
`/app/user-data/conf.yml` on the volume to configure it.

## Security and persistence

The image rebuilds its assets on a config change and writes across the root
filesystem, so this workload relaxes kurly's read-only-rootfs default while keeping
non-root, dropped capabilities, and no privilege escalation. The configuration lives
on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: dashy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dashy, namespace: dashy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dashy, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dashy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dashy, namespace: dashy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dashy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dashy, namespace: dashy }
spec:
  serviceAccountName: dashy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/dashy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dashy, importPath: github.com/metio/kurly/workloads/dashy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dashy, namespace: dashy }
spec:
  serviceAccountName: dashy-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dashy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: dashy }
```

<!-- END generated: jaas-deploy -->
