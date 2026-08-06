<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fittrackee

[FitTrackee](https://github.com/SamR1/FitTrackee) — a self-hosted workout and
activity tracker: GPX/FIT uploads, maps and statistics. A plain composable
`kurly.http` workload backed by an external PostgreSQL, with uploaded activity
files and pictures on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fittrackee = import 'github.com/metio/kurly/workloads/fittrackee/server.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  valkey(name='fittrackee-cache'),
  fittrackee(
    uiUrl='https://fittrackee.example.com',
    redisUrl='redis://fittrackee-cache:6379',
  ),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `fittrackee` | |
| `image` | the pinned FitTrackee image | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploads and map cache (`/data`) |
| `uiUrl` | `https://fittrackee.example.com` | the origin browsers reach it at — replace it |
| `redisUrl` | unset | an optional Redis/valkey |
| `workers` | `1` | gunicorn workers in the pod |
| `secretName` | `fittrackee` | Secret with `DATABASE_URL` and `APP_SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:5000` — compose an exposure onto it.

## The database needs PostGIS

FitTrackee v1+ stores geospatial data, so the PostgreSQL it connects to must have
the **PostGIS** extension available and enabled in its database. On a plain
PostgreSQL the start-up migration fails, and the pod restarts forever with nothing
to show for it. A [cnpg-cluster](../cnpg-cluster/) can serve it from a PostGIS
image; a stock `postgres` image cannot.

## Secrets

`DATABASE_URL` carries the database password and `APP_SECRET_KEY` signs sessions,
so both come from a provided Secret via `envFrom`. kurly authors **no Secret** —
fill `fittrackee` with [`kurly.externalSecret`](../../main.libsonnet) or your own
generator.

## Redis is optional

Without one, the API rate limits, the background workers (data export, workout
archive uploads) and e-mail sending are off; the application checks at start-up and
carries on. Point `redisUrl` at a [valkey](../valkey/) to switch them on. Setting
`EMAIL_URL` through `env` without a reachable Redis makes the application refuse to
start, which is upstream's own check and not this workload's.

## Persistence

Uploads and the static-map cache live on a ReadWriteOnce volume, so this is **one
replica, recreated**.

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
metadata: { name: kurly, namespace: fittrackee }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-fittrackee, namespace: fittrackee }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/fittrackee, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: fittrackee }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-fittrackee, namespace: fittrackee }
spec: { sourceRef: { kind: OCIRepository, name: kurly-fittrackee } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: fittrackee, namespace: fittrackee }
spec:
  serviceAccountName: fittrackee-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/fittrackee/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-fittrackee, importPath: github.com/metio/kurly/workloads/fittrackee }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: fittrackee, namespace: fittrackee }
spec:
  serviceAccountName: fittrackee-deployer
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
        name: fittrackee
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: fittrackee }
```

<!-- END generated: jaas-deploy -->
