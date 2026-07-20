<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# photoview

[Photoview](https://photoview.github.io) — a self-hosted photo gallery for photographers: it
scans a media library, builds albums and serves them with face recognition and RAW support. A
`kurly.http` workload on the official image, backed by an external MySQL/MariaDB or PostgreSQL,
with **two PersistentVolumes** — the media library and a thumbnail cache.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local photoview = import 'github.com/metio/kurly/workloads/photoview/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(mysql(name='photoview-db')).items,
  kurly.list(photoview()).items,
]))
```

Photoview keeps two directories on disk — the media library at `/photos` (add photos there to
scan) and the cache at `/app/cache` — so the workload composes `kurly.store` **twice**, one PVC
each (sized by `mediaSize`/`cacheSize`). The database driver and connection
(`PHOTOVIEW_DATABASE_DRIVER`, `PHOTOVIEW_MYSQL_URL` / `PHOTOVIEW_POSTGRES_URL`) come from a Secret
via `envFrom` — kurly authors **no Secret**. Both volumes are ReadWriteOnce, so this is **one
replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: photoview }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-photoview, namespace: photoview }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/photoview, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: photoview }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-photoview, namespace: photoview }
spec: { sourceRef: { kind: OCIRepository, name: kurly-photoview } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: photoview, namespace: photoview }
spec:
  serviceAccountName: photoview-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/photoview/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-photoview, importPath: github.com/metio/kurly/workloads/photoview }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: photoview, namespace: photoview }
spec:
  serviceAccountName: photoview-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: photoview
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: photoview }
```

<!-- END generated: jaas-deploy -->
