<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# leantime

[Leantime](https://leantime.io) — a self-hosted, open-source project-management system for non-project-managers: goals, ideas, tasks, time tracking. A `kurly.http` workload on the official image, backed by an external MySQL/MariaDB; uploaded files on a PersistentVolume under `/var/www/html/userfiles`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local leantime = import 'github.com/metio/kurly/workloads/leantime/server.libsonnet';
kurly.list(leantime())
```

Uploads at `/var/www/html/userfiles` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

**Secrets:** Leantime reads `LEAN_DB_*` and `LEAN_SESSION_PASSWORD` from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. Pair it with a MySQL/MariaDB you run separately.

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
metadata: { name: kurly, namespace: leantime }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-leantime, namespace: leantime }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/leantime, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: leantime }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-leantime, namespace: leantime }
spec: { sourceRef: { kind: OCIRepository, name: kurly-leantime } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: leantime, namespace: leantime }
spec:
  serviceAccountName: leantime-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/leantime/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-leantime, importPath: github.com/metio/kurly/workloads/leantime }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: leantime, namespace: leantime }
spec:
  serviceAccountName: leantime-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: leantime
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: leantime }
```

<!-- END generated: jaas-deploy -->
