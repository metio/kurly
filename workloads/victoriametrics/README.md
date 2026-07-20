<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# victoriametrics

[VictoriaMetrics](https://victoriametrics.com) — a fast, cost-effective, self-hosted time-series database and Prometheus-compatible monitoring backend. A `kurly.http` workload on the official single-node image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local victoriametrics = import 'github.com/metio/kurly/workloads/victoriametrics/server.libsonnet';
kurly.list(victoriametrics())
```

`retentionPeriod` is in months (e.g. `'12'`). Data at `/victoria-metrics-data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8428`.

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
metadata: { name: kurly, namespace: victoriametrics }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-victoriametrics, namespace: victoriametrics }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/victoriametrics, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: victoriametrics }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-victoriametrics, namespace: victoriametrics }
spec: { sourceRef: { kind: OCIRepository, name: kurly-victoriametrics } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: victoriametrics, namespace: victoriametrics }
spec:
  serviceAccountName: victoriametrics-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/victoriametrics/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-victoriametrics, importPath: github.com/metio/kurly/workloads/victoriametrics }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: victoriametrics, namespace: victoriametrics }
spec:
  serviceAccountName: victoriametrics-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: victoriametrics
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: victoriametrics }
```

<!-- END generated: jaas-deploy -->
