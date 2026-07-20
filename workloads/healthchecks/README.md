<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# healthchecks

[Healthchecks](https://healthchecks.io) — a self-hosted cron-job and background-task
monitoring service: your jobs ping a URL when they finish, and it alerts you when a ping is
late or missing. A plain composable `kurly.http` workload on the official image; with the
default SQLite backend its database lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local healthchecks = import 'github.com/metio/kurly/workloads/healthchecks/server.libsonnet';
kurly.list(healthchecks(siteRoot='https://checks.example.com', allowedHosts='checks.example.com'))
```

Healthchecks needs `SECRET_KEY` from a Secret via `envFrom` — kurly authors **no Secret**.
Point it at an external PostgreSQL (`DB=postgres` plus the `DB_*` connection) to scale past
SQLite. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8000`.

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
metadata: { name: kurly, namespace: healthchecks }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-healthchecks, namespace: healthchecks }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/healthchecks, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: healthchecks }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-healthchecks, namespace: healthchecks }
spec: { sourceRef: { kind: OCIRepository, name: kurly-healthchecks } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: healthchecks, namespace: healthchecks }
spec:
  serviceAccountName: healthchecks-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/healthchecks/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-healthchecks, importPath: github.com/metio/kurly/workloads/healthchecks }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: healthchecks, namespace: healthchecks }
spec:
  serviceAccountName: healthchecks-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: healthchecks
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: healthchecks }
```

<!-- END generated: jaas-deploy -->
