<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# typesense

[Typesense](https://typesense.org) — a fast, typo-tolerant, self-hosted search engine with a clean API. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local typesense = import 'github.com/metio/kurly/workloads/typesense/server.libsonnet';
kurly.list(typesense())
```

`TYPESENSE_API_KEY` comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8108`.

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
metadata: { name: kurly, namespace: typesense }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-typesense, namespace: typesense }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/typesense, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: typesense }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-typesense, namespace: typesense }
spec: { sourceRef: { kind: OCIRepository, name: kurly-typesense } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: typesense, namespace: typesense }
spec:
  serviceAccountName: typesense-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/typesense/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-typesense, importPath: github.com/metio/kurly/workloads/typesense }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: typesense, namespace: typesense }
spec:
  serviceAccountName: typesense-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: typesense
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: typesense }
```

<!-- END generated: jaas-deploy -->
