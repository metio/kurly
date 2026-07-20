<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kutt

[Kutt](https://kutt.it) — a free, self-hosted modern URL shortener with custom domains, link analytics and an API. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kutt = import 'github.com/metio/kurly/workloads/kutt/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='kutt-db', database='kutt')).items,
  kurly.list(kutt()).items,
]))
```

The PostgreSQL/Redis connection, `JWT_SECRET` and `DEFAULT_DOMAIN` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (links live in PostgreSQL). Serves on `:3000`.

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
metadata: { name: kurly, namespace: kutt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kutt, namespace: kutt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kutt, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kutt }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kutt, namespace: kutt }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kutt } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kutt, namespace: kutt }
spec:
  serviceAccountName: kutt-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/kutt/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kutt, importPath: github.com/metio/kurly/workloads/kutt }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kutt, namespace: kutt }
spec:
  serviceAccountName: kutt-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kutt
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kutt }
```

<!-- END generated: jaas-deploy -->
