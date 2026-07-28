<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# seatsurfing

[Seatsurfing](https://github.com/seatsurfing/seatsurfing) — desk and meeting-room
booking / hot-desking. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local seatsurfing = import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet';

kurly.list(seatsurfing(env={ PUBLIC_URL: 'https://booking.example.com' }))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `seatsurfing` | |
| `image` | `ghcr.io/seatsurfing/seatsurfing:1.116.0` | |
| `secretName` | `seatsurfing-secrets` | Secret with `POSTGRES_URL` and `JWT_SIGNING_KEY` (envFrom) |
| `replicas` | `1` | stateless — scale out freely |
| `env` | `{}` | non-sensitive settings (`PUBLIC_URL`, `FRONTEND_URL`) |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Database and secrets

Seatsurfing reads `POSTGRES_URL` and `JWT_SIGNING_KEY` from the environment. kurly
authors **no Secret** — provide `seatsurfing-secrets` holding both (the database
password is embedded in `POSTGRES_URL`), pulled in via `envFrom`. Fill it with
[`kurly.externalSecret`](../../main.libsonnet). The defaults pair with a
[cnpg-cluster](../cnpg-cluster/) named `seatsurfing-db`. Being stateless, it can run
several replicas.

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
metadata: { name: kurly, namespace: seatsurfing }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-seatsurfing, namespace: seatsurfing }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/seatsurfing, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: seatsurfing }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-seatsurfing, namespace: seatsurfing }
spec: { sourceRef: { kind: OCIRepository, name: kurly-seatsurfing } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: seatsurfing, namespace: seatsurfing }
spec:
  serviceAccountName: seatsurfing-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-seatsurfing, importPath: github.com/metio/kurly/workloads/seatsurfing }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: seatsurfing, namespace: seatsurfing }
spec:
  serviceAccountName: seatsurfing-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: seatsurfing
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: seatsurfing }
```

<!-- END generated: jaas-deploy -->
