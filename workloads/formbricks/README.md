<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# formbricks

[Formbricks](https://formbricks.com) — a self-hosted, open-source experience-management and survey platform. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local formbricks = import 'github.com/metio/kurly/workloads/formbricks/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='formbricks-db', database='formbricks')).items,
  kurly.list(formbricks(webappUrl='https://surveys.example.com')).items,
]))
```

`DATABASE_URL`, `NEXTAUTH_SECRET` and `ENCRYPTION_KEY` come from a Secret via `envFrom` — kurly authors **no Secret**. Stateless. Serves on `:3000`.

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
metadata: { name: kurly, namespace: formbricks }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-formbricks, namespace: formbricks }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/formbricks, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: formbricks }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-formbricks, namespace: formbricks }
spec: { sourceRef: { kind: OCIRepository, name: kurly-formbricks } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: formbricks, namespace: formbricks }
spec:
  serviceAccountName: formbricks-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/formbricks/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-formbricks, importPath: github.com/metio/kurly/workloads/formbricks }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: formbricks, namespace: formbricks }
spec:
  serviceAccountName: formbricks-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: formbricks
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: formbricks }
```

<!-- END generated: jaas-deploy -->
