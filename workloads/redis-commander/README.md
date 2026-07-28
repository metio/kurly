<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redis-commander

[Redis Commander](https://github.com/joeferner/redis-commander) — a self-hosted web UI for managing Redis. A **stateless** `kurly.http` workload on the official image (pinned by digest — Renovate maintains it).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rc = import 'github.com/metio/kurly/workloads/redis-commander/server.libsonnet';
kurly.list(rc(redisHosts='local:redis:6379'))
```

Point it at Redis through `redisHosts` (`REDIS_HOSTS`). Serves on `:8081`.

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
metadata: { name: kurly, namespace: redis-commander }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-redis-commander, namespace: redis-commander }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/redis-commander, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: redis-commander }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-redis-commander, namespace: redis-commander }
spec: { sourceRef: { kind: OCIRepository, name: kurly-redis-commander } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redis-commander, namespace: redis-commander }
spec:
  serviceAccountName: redis-commander-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/redis-commander/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redis-commander, importPath: github.com/metio/kurly/workloads/redis-commander }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: redis-commander, namespace: redis-commander }
spec:
  serviceAccountName: redis-commander-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redis-commander
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redis-commander }
```

<!-- END generated: jaas-deploy -->
