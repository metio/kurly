<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongo

MongoDB server — a self-hosted, document-oriented NoSQL database. A `kurly.http` workload (for its Deployment/Service plumbing) on the official image; the server speaks its own protocol on `:27017`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongo = import 'github.com/metio/kurly/workloads/mongo/server.libsonnet';
kurly.list(mongo())
```

A **single instance** (not a replicated cluster — use the operator-backed cluster workloads for HA). Credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data/db` on a ReadWriteOnce volume, so **one replica, recreated**. Reached in-cluster on `:27017`.

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
metadata: { name: kurly, namespace: mongo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mongo, namespace: mongo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mongo, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mongo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mongo, namespace: mongo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mongo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mongo, namespace: mongo }
spec:
  serviceAccountName: mongo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mongo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mongo, importPath: github.com/metio/kurly/workloads/mongo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mongo, namespace: mongo }
spec:
  serviceAccountName: mongo-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mongo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mongo }
```

<!-- END generated: jaas-deploy -->
