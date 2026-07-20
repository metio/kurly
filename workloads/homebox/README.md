<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homebox

[Homebox](https://github.com/sysadminsmedia/homebox) — a simple home/household
inventory and asset manager. A plain composable `kurly.http` workload on the
**rootless** image that keeps its inventory in a SQLite database and uploaded
attachments on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homebox = import 'github.com/metio/kurly/workloads/homebox/server.libsonnet';

kurly.list(homebox())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `homebox` | |
| `image` | `ghcr.io/sysadminsmedia/homebox:0.26.2-rootless` | the rootless variant |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the data volume (`/data`) |
| `env` | `{}` | extra `HBOX_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:7745` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  homebox()
  + kurly.expose.ownGateway('inventory.example.com', 'istio', tls='homebox-tls'),
  kurly.certificate('homebox-tls', ['inventory.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the file — the same single-writer discipline as
[vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: homebox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-homebox, namespace: homebox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/homebox, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: homebox }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-homebox, namespace: homebox }
spec: { sourceRef: { kind: OCIRepository, name: kurly-homebox } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: homebox, namespace: homebox }
spec:
  serviceAccountName: homebox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/homebox/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-homebox, importPath: github.com/metio/kurly/workloads/homebox }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: homebox, namespace: homebox }
spec:
  serviceAccountName: homebox-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: homebox
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: homebox }
```

<!-- END generated: jaas-deploy -->
