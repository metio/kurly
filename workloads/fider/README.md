<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fider

[Fider](https://github.com/getfider/fider) — an open-source platform to collect and
prioritize customer feedback. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fider = import 'github.com/metio/kurly/workloads/fider/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='fider-db', database='fider')).items,
  kurly.list(fider(baseUrl='https://feedback.example.com')).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `fider` | |
| `image` | `docker.io/getfider/fider:v0.36.0` | |
| `baseUrl` | inferred | the public URL |
| `secretName` | `fider-secrets` | Secret with `DATABASE_URL`, `JWT_SECRET`, `EMAIL_*` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Fider reads `DATABASE_URL` (with the database password embedded), `JWT_SECRET`, and
its SMTP/email credentials from the environment. kurly authors **no Secret** — provide
`fider-secrets` holding them, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `fider-db`. Being stateless, it can run several
replicas.

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
metadata: { name: kurly, namespace: fider }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-fider, namespace: fider }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/fider, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: fider }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-fider, namespace: fider }
spec: { sourceRef: { kind: OCIRepository, name: kurly-fider } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: fider, namespace: fider }
spec:
  serviceAccountName: fider-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/fider/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-fider, importPath: github.com/metio/kurly/workloads/fider }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: fider, namespace: fider }
spec:
  serviceAccountName: fider-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: fider
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: fider }
```

<!-- END generated: jaas-deploy -->
