<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# outline

[Outline](https://www.getoutline.com) — a fast, collaborative, self-hosted team knowledge base and wiki with real-time editing. A `kurly.http` workload on the official image, backed by an external PostgreSQL, Redis and S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local outline = import 'github.com/metio/kurly/workloads/outline/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.list([
  cnpg(name='outline-db', database='outline'),
  outline(url='https://wiki.example.com'),
])
```

`DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `UTILS_SECRET`, the S3 settings and an auth provider come from a Secret via `envFrom` — kurly authors **no Secret**. Uploads go to S3 (pair with [seaweedfs](../seaweedfs/)). Stateless. Serves on `:3000`.

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
metadata: { name: kurly, namespace: outline }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-outline, namespace: outline }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/outline, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: outline }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-outline, namespace: outline }
spec: { sourceRef: { kind: OCIRepository, name: kurly-outline } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: outline, namespace: outline }
spec:
  serviceAccountName: outline-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/outline/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-outline, importPath: github.com/metio/kurly/workloads/outline }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: outline, namespace: outline }
spec:
  serviceAccountName: outline-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: outline
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: outline }
```

<!-- END generated: jaas-deploy -->
