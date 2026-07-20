<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# davis

[Davis](https://github.com/tchapi/davis) — a self-hosted CalDAV and CardDAV server with a simple admin UI, built on sabre/dav. A `kurly.http` workload on the official image, backed by an external database (MySQL/MariaDB, PostgreSQL, or SQLite).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local davis = import 'github.com/metio/kurly/workloads/davis/server.libsonnet';
kurly.list(davis())
```

Stateless — calendars and contacts live in the database, so a plain rolling Deployment. Serves the web UI and CalDAV/CardDAV endpoints on `:80`.

**Secrets:** Davis reads `DATABASE_URL`, `APP_SECRET` and the admin login from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. Pair it with a database you run separately (e.g. a `cnpg-cluster` named `davis-db`).

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
metadata: { name: kurly, namespace: davis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-davis, namespace: davis }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/davis, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: davis }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-davis, namespace: davis }
spec: { sourceRef: { kind: OCIRepository, name: kurly-davis } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: davis, namespace: davis }
spec:
  serviceAccountName: davis-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/davis/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-davis, importPath: github.com/metio/kurly/workloads/davis }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: davis, namespace: davis }
spec:
  serviceAccountName: davis-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: davis
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: davis }
```

<!-- END generated: jaas-deploy -->
