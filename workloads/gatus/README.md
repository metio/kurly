<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gatus

[Gatus](https://github.com/TwiN/gatus) — a self-hosted, developer-oriented health
dashboard and status page: it probes your endpoints on a schedule, evaluates conditions
and alerts. A plain composable `kurly.http` workload on the official image; its
configuration is mounted as a ConfigMap and its history database lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gatus = import 'github.com/metio/kurly/workloads/gatus/server.libsonnet';

kurly.list(gatus(config={
  storage: { type: 'sqlite', path: '/data/gatus.db' },
  endpoints: [
    { name: 'api', url: 'https://api.example.com/health', interval: '1m',
      conditions: ['[STATUS] == 200', '[RESPONSE_TIME] < 300'] },
  ],
}))
```

`config` is Gatus's own schema (endpoints, conditions, alerting, storage, ui), rendered to
the mounted `config.yaml` verbatim — kurly does not model it. The default watches one
sample endpoint and persists history to SQLite on the data volume; replace it with your
own. History at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8080`.

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
metadata: { name: kurly, namespace: gatus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gatus, namespace: gatus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gatus, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gatus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gatus, namespace: gatus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gatus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gatus, namespace: gatus }
spec:
  serviceAccountName: gatus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gatus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gatus, importPath: github.com/metio/kurly/workloads/gatus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gatus, namespace: gatus }
spec:
  serviceAccountName: gatus-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: gatus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gatus }
```

<!-- END generated: jaas-deploy -->
