<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redmine

[Redmine](https://www.redmine.org) — a mature, self-hosted project-management web app: issue tracking, wikis, forums, Gantt charts and time tracking. A `kurly.http` workload on the official image, backed by an external MySQL/MariaDB or PostgreSQL, with uploaded files on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redmine = import 'github.com/metio/kurly/workloads/redmine/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.list([
  mysql(name='redmine-db'),
  redmine(),
])
```

The database connection and `REDMINE_SECRET_KEY_BASE` come from a Secret via `envFrom` — kurly authors **no Secret**. Files at `/usr/src/redmine/files` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.

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
metadata: { name: kurly, namespace: redmine }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-redmine, namespace: redmine }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/redmine, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: redmine }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-redmine, namespace: redmine }
spec: { sourceRef: { kind: OCIRepository, name: kurly-redmine } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redmine, namespace: redmine }
spec:
  serviceAccountName: redmine-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/redmine/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redmine, importPath: github.com/metio/kurly/workloads/redmine }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: redmine, namespace: redmine }
spec:
  serviceAccountName: redmine-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redmine
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redmine }
```

<!-- END generated: jaas-deploy -->
