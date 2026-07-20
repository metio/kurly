<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mealie

[Mealie](https://mealie.io) — a self-hosted recipe manager and meal planner with a recipe
scraper, shopping lists and a REST API. A plain composable `kurly.http` workload on the
official image; with the default SQLite backend its database and uploaded assets live on
a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mealie = import 'github.com/metio/kurly/workloads/mealie/server.libsonnet';
kurly.list(mealie(baseUrl='https://recipes.example.com'))
```

Point Mealie at an external PostgreSQL (`DB_ENGINE=postgres` plus the `POSTGRES_*`
connection) to scale past the single SQLite writer. Data at `/app/data` on a ReadWriteOnce
volume, so **one replica, recreated**. Serves on `:9000`.

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
metadata: { name: kurly, namespace: mealie }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mealie, namespace: mealie }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mealie, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mealie }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mealie, namespace: mealie }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mealie } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mealie, namespace: mealie }
spec:
  serviceAccountName: mealie-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mealie/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mealie, importPath: github.com/metio/kurly/workloads/mealie }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mealie, namespace: mealie }
spec:
  serviceAccountName: mealie-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mealie
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mealie }
```

<!-- END generated: jaas-deploy -->
