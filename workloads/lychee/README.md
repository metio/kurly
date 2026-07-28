<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lychee

[Lychee](https://github.com/LycheeOrg/Lychee) — a self-hosted photo-management and
gallery system. A plain composable `kurly.http` workload on the official image: with
the SQLite backend its config, database, and photos live on a PersistentVolume, so it
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lychee = import 'github.com/metio/kurly/workloads/lychee/server.libsonnet';

kurly.list(lychee(appUrl='https://photos.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `lychee` | |
| `image` | `docker.io/lycheeorg/lychee:v7.7.1` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | photos (`/uploads`), config (`/conf`), symlinks (`/sym`) |
| `appUrl` | inferred | the public URL |
| `secretName` | `lychee-secrets` | Secret with `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the gallery and API on `:80` — compose an exposure onto it.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Config, database, and photos live on a ReadWriteOnce volume,
so this is **one replica, recreated**. Point `DB_CONNECTION` at external MySQL/PostgreSQL
to scale past the single SQLite writer.

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
metadata: { name: kurly, namespace: lychee }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lychee, namespace: lychee }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lychee, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lychee }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lychee, namespace: lychee }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lychee } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lychee, namespace: lychee }
spec:
  serviceAccountName: lychee-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lychee/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lychee, importPath: github.com/metio/kurly/workloads/lychee }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lychee, namespace: lychee }
spec:
  serviceAccountName: lychee-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: lychee
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lychee }
```

<!-- END generated: jaas-deploy -->
