<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rallly

[Rallly](https://github.com/lukevella/rallly) — a self-hosted scheduling and
group-poll tool for finding the best date to meet. A plain composable `kurly.http`
workload on the official image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rallly = import 'github.com/metio/kurly/workloads/rallly/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='rallly-db', database='rallly'),
  rallly(baseUrl='https://rallly.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `rallly` | |
| `image` | `ghcr.io/lukevella/rallly:4.11.1` | |
| `baseUrl` | inferred | the public URL |
| `secretName` | `rallly-secrets` | Secret with `DATABASE_URL`, `SECRET_PASSWORD`, `SMTP_*` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Database and secrets

Rallly reads `DATABASE_URL` (with the database password embedded), `SECRET_PASSWORD`,
and its SMTP credentials from the environment. kurly authors **no Secret** — provide
`rallly-secrets` holding them, pulled in via `envFrom` (fill it with
[`kurly.externalSecret`](../../main.libsonnet)). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `rallly-db`. Being stateless, it can run several
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
metadata: { name: kurly, namespace: rallly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-rallly, namespace: rallly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/rallly, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: rallly }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-rallly, namespace: rallly }
spec: { sourceRef: { kind: OCIRepository, name: kurly-rallly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: rallly, namespace: rallly }
spec:
  serviceAccountName: rallly-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/rallly/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-rallly, importPath: github.com/metio/kurly/workloads/rallly }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: rallly, namespace: rallly }
spec:
  serviceAccountName: rallly-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: rallly
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: rallly }
```

<!-- END generated: jaas-deploy -->
