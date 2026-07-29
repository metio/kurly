<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# planka

[Planka](https://planka.app) — a self-hosted, real-time kanban board for teams, an open alternative to Trello. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with uploads in S3-compatible object storage.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local planka = import 'github.com/metio/kurly/workloads/planka/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.list([
  cnpg(name='planka-db', database='planka'),
  planka(baseUrl='https://boards.example.com'),
])
```

`DATABASE_URL`, `SECRET_KEY`, the `S3_*` settings and the admin credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Uploads go to S3 (pair with [seaweedfs](../seaweedfs/)), so this is **stateless**. For local-disk uploads instead, compose ReadWriteMany volumes onto the three upload paths and drop the S3 settings. Serves on `:1337`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: planka }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-planka, namespace: planka }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/planka, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: planka }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-planka, namespace: planka }
spec: { sourceRef: { kind: OCIRepository, name: kurly-planka } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: planka, namespace: planka }
spec:
  serviceAccountName: planka-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/planka/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-planka, importPath: github.com/metio/kurly/workloads/planka }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: planka, namespace: planka }
spec:
  serviceAccountName: planka-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: planka
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: planka }
```

<!-- END generated: jaas-deploy -->
