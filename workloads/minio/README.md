<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# minio

[MinIO](https://min.io) — a high-performance, self-hosted, S3-compatible object storage server. A `kurly.http` workload on the official image; objects on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local minio = import 'github.com/metio/kurly/workloads/minio/server.libsonnet';
kurly.list(minio())
```

Single-node MinIO. `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` come from a Secret via `envFrom` — kurly authors **no Secret**. The web console (`:9001`) needs an extra Service. Objects at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the S3 API on `:9000`.

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
metadata: { name: kurly, namespace: minio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-minio, namespace: minio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/minio, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: minio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-minio, namespace: minio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-minio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: minio, namespace: minio }
spec:
  serviceAccountName: minio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/minio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-minio, importPath: github.com/metio/kurly/workloads/minio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: minio, namespace: minio }
spec:
  serviceAccountName: minio-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: minio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: minio }
```

<!-- END generated: jaas-deploy -->
