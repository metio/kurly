<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redis

Redis server — an in-memory data store used as a cache, message broker and database. A `kurly.http` workload (for its Deployment/Service plumbing) on the official image; the server speaks its own protocol on `:6379`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redis = import 'github.com/metio/kurly/workloads/redis/server.libsonnet';
kurly.list(redis())
```

A **single instance** (not a replicated cluster — use the operator-backed cluster workloads for HA). Credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Reached in-cluster on `:6379`.

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
metadata: { name: kurly, namespace: redis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-redis, namespace: redis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/redis, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: redis }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-redis, namespace: redis }
spec: { sourceRef: { kind: OCIRepository, name: kurly-redis } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redis, namespace: redis }
spec:
  serviceAccountName: redis-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/redis/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redis, importPath: github.com/metio/kurly/workloads/redis }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: redis, namespace: redis }
spec:
  serviceAccountName: redis-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redis
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redis }
```

<!-- END generated: jaas-deploy -->
