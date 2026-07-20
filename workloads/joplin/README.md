<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# joplin

[Joplin Server](https://github.com/laurent22/joplin) — the self-hosted sync target for the Joplin note-taking apps. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local joplin = import 'github.com/metio/kurly/workloads/joplin/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='joplin-db', database='joplin')).items,
  kurly.list(joplin(appBaseUrl='https://joplin.example.com')).items,
]))
```

The `POSTGRES_*` connection comes from a Secret via `envFrom` — kurly authors **no Secret**. Stateless (notes live in PostgreSQL). Serves on `:22300`.

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
metadata: { name: kurly, namespace: joplin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-joplin, namespace: joplin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/joplin, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: joplin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-joplin, namespace: joplin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-joplin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: joplin, namespace: joplin }
spec:
  serviceAccountName: joplin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/joplin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-joplin, importPath: github.com/metio/kurly/workloads/joplin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: joplin, namespace: joplin }
spec:
  serviceAccountName: joplin-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: joplin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: joplin }
```

<!-- END generated: jaas-deploy -->
