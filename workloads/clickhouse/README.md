<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# clickhouse

[ClickHouse](https://clickhouse.com) — a fast, self-hosted column-oriented SQL database for real-time analytics. A `kurly.http` workload on the official single-node image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local clickhouse = import 'github.com/metio/kurly/workloads/clickhouse/server.libsonnet';
kurly.list(clickhouse())
```

`CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD` / `CLICKHOUSE_DB` come from a Secret via `envFrom` — kurly authors **no Secret**. The native protocol (`:9000`) needs an extra Service. Data at `/var/lib/clickhouse` on a ReadWriteOnce volume, so **one replica, recreated**. Serves HTTP on `:8123`.

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
metadata: { name: kurly, namespace: clickhouse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-clickhouse, namespace: clickhouse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/clickhouse, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: clickhouse }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-clickhouse, namespace: clickhouse }
spec: { sourceRef: { kind: OCIRepository, name: kurly-clickhouse } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: clickhouse, namespace: clickhouse }
spec:
  serviceAccountName: clickhouse-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/clickhouse/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-clickhouse, importPath: github.com/metio/kurly/workloads/clickhouse }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: clickhouse, namespace: clickhouse }
spec:
  serviceAccountName: clickhouse-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: clickhouse
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: clickhouse }
```

<!-- END generated: jaas-deploy -->
