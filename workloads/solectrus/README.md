<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# solectrus

[SOLECTRUS](https://github.com/solectrus/solectrus) — a photovoltaic dashboard: what
the panels produce, what the house consumes, what goes to and comes from the grid, and
what that is worth. A plain composable `kurly.http` workload on the official image,
backed by an InfluxDB, a PostgreSQL and a Redis.

This is the **dashboard only**. The measurements it draws are written to InfluxDB by
collectors that run beside a PV system (an inverter reader, a wallbox reader, a
heat-pump reader) and are not carried here, so a fresh instance with nothing feeding it
renders empty rather than broken.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local solectrus = import 'github.com/metio/kurly/workloads/solectrus/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='solectrus-db', database='solectrus_production'),
  solectrus(appHost='pv.example.com', installationDate='2021-06-14'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `solectrus` | |
| `image` | the pinned official image | |
| `replicas` | `1` | stateless — scale freely |
| `secretName` | `solectrus` | `DB_PASSWORD`, `REDIS_URL`, `INFLUX_TOKEN`, `SECRET_KEY_BASE`, `ADMIN_PASSWORD` (envFrom) |
| `dbHost` / `dbPort` / `dbUser` | `solectrus-db-rw` / `5432` / `solectrus` | the database itself must be named `solectrus_production` |
| `influxHost` / `influxPort` / `influxScheme` | `influxdb` / `8086` / `http` | |
| `influxOrg` / `influxBucket` | `solectrus` / `solectrus` | must match what the collectors write into |
| `appHost` | `solectrus.example.com` | the host a browser reaches it at; Rails checks it |
| `forceSsl` | `false` | on where the pod is reached directly over TLS |
| `installationDate` | `2025-01-01` | the day the system first produced anything |
| `timezone` | `Europe/Berlin` | |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Backends and secrets

All three backends are required, and the entrypoint refuses to start without
`DB_HOST`, `INFLUX_HOST` and `REDIS_URL`: a missing one is a pod that never listens
rather than one that answers wrongly. It waits for each in turn and then runs
`rails db:prepare`, which is why the stage carries a startup probe rather than a longer
liveness delay.

- **InfluxDB 2** holds the measurements. `INFLUX_TOKEN` only has to be able to *read*
  the bucket — giving it the admin token hands a browser-facing app write access to the
  whole measurement history.
- **PostgreSQL** holds SOLECTRUS' own records. The database name is hard-coded to
  `solectrus_production` in the application's `config/database.yml`, so the server the
  defaults pair with — a [cnpg-cluster](../cnpg-cluster/) named `solectrus-db` — has to
  create it under that name.
- **Redis** is the cache and the ActionCable backend, addressed by the whole
  `REDIS_URL`.

kurly authors **no Secret** — provide one holding `DB_PASSWORD`, `REDIS_URL`,
`INFLUX_TOKEN`, `SECRET_KEY_BASE` and `ADMIN_PASSWORD`. `SECRET_KEY_BASE` signs the
session cookies, so a value that changes on every restart signs everybody out;
`ADMIN_PASSWORD` guards the settings the dashboard can change.

## Probes and exposure

Rails checks the request's `Host` header against `APP_HOST` and answers 403 to anything
else, and with `forceSsl` on it redirects a plain request to `https` — either kills an
HTTP probe, so readiness and liveness are **connection** checks.

## Persistence

Everything is in PostgreSQL, InfluxDB and Redis, so this is **stateless** — a plain
rolling Deployment with no volume.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: solectrus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-solectrus, namespace: solectrus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/solectrus, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: solectrus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-solectrus, namespace: solectrus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-solectrus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: solectrus, namespace: solectrus }
spec:
  serviceAccountName: solectrus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/solectrus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-solectrus, importPath: github.com/metio/kurly/workloads/solectrus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: solectrus, namespace: solectrus }
spec:
  serviceAccountName: solectrus-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: solectrus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: solectrus }
```

<!-- END generated: jaas-deploy -->
