<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homer

[Homer](https://github.com/bastienwirtz/homer) — a simple, static dashboard for your
self-hosted services. A plain composable `kurly.http` workload on the official
image; its configuration and custom assets live on a PersistentVolume, so it needs
no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homer = import 'github.com/metio/kurly/workloads/homer/server.libsonnet';

kurly.list(homer())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homer` | |
| `image` | `docker.io/b4bz/homer:v26.4.2` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | assets and `config.yml` (`/www/assets`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:8080` — compose an exposure onto it. Edit
`/www/assets/config.yml` on the volume to configure it (the image seeds defaults on
first start via `INIT_ASSETS`).

## Persistence

The assets live on a ReadWriteOnce volume, so this is **one replica, recreated** —
the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: homer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-homer, namespace: homer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/homer, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: homer }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-homer, namespace: homer }
spec: { sourceRef: { kind: OCIRepository, name: kurly-homer } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: homer, namespace: homer }
spec:
  serviceAccountName: homer-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/homer/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-homer, importPath: github.com/metio/kurly/workloads/homer }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: homer, namespace: homer }
spec:
  serviceAccountName: homer-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: homer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: homer }
```

<!-- END generated: jaas-deploy -->
