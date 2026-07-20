<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# influxdb

[InfluxDB 2](https://www.influxdata.com) — a self-hosted time-series database for metrics, events and IoT data, with a built-in UI and query engine. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local influxdb = import 'github.com/metio/kurly/workloads/influxdb/server.libsonnet';
kurly.list(influxdb())
```

The `DOCKER_INFLUXDB_INIT_*` setup values come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/lib/influxdb2` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8086`.

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
metadata: { name: kurly, namespace: influxdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-influxdb, namespace: influxdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/influxdb, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: influxdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-influxdb, namespace: influxdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly-influxdb } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: influxdb, namespace: influxdb }
spec:
  serviceAccountName: influxdb-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/influxdb/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-influxdb, importPath: github.com/metio/kurly/workloads/influxdb }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: influxdb, namespace: influxdb }
spec:
  serviceAccountName: influxdb-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: influxdb
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: influxdb }
```

<!-- END generated: jaas-deploy -->
