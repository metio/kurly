<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kimai

[Kimai](https://www.kimai.org) — a self-hosted, professional time-tracking application for freelancers and teams. A `kurly.http` workload on the official Apache image, backed by an external MySQL/MariaDB.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kimai = import 'github.com/metio/kurly/workloads/kimai/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.list([
  mysql(name='kimai-db'),
  kimai(),
])
```

`DATABASE_URL` and `APP_SECRET` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (timesheets live in MySQL). Serves on `:8001`.

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
metadata: { name: kurly, namespace: kimai }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kimai, namespace: kimai }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kimai, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kimai }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kimai, namespace: kimai }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kimai } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kimai, namespace: kimai }
spec:
  serviceAccountName: kimai-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/kimai/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kimai, importPath: github.com/metio/kurly/workloads/kimai }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kimai, namespace: kimai }
spec:
  serviceAccountName: kimai-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kimai
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kimai }
```

<!-- END generated: jaas-deploy -->
