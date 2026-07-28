<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# qdrant

[Qdrant](https://qdrant.tech) — a self-hosted vector database and similarity-search engine for embeddings (AI/semantic-search and RAG). A `kurly.http` workload on the official image; collections on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local qdrant = import 'github.com/metio/kurly/workloads/qdrant/server.libsonnet';
kurly.list(qdrant())
```

gRPC on `:6334` needs an extra Service. Collections at `/qdrant/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the REST API on `:6333`.

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
metadata: { name: kurly, namespace: qdrant }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-qdrant, namespace: qdrant }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/qdrant, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: qdrant }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-qdrant, namespace: qdrant }
spec: { sourceRef: { kind: OCIRepository, name: kurly-qdrant } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: qdrant, namespace: qdrant }
spec:
  serviceAccountName: qdrant-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/qdrant/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-qdrant, importPath: github.com/metio/kurly/workloads/qdrant }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: qdrant, namespace: qdrant }
spec:
  serviceAccountName: qdrant-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: qdrant
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: qdrant }
```

<!-- END generated: jaas-deploy -->
