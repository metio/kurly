<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wger

[wger](https://github.com/wger-project/wger) — a self-hosted workout, nutrition,
and body-weight manager. A plain composable `kurly.http` workload on the official
all-in-one image, backed by an external PostgreSQL and Redis, with its uploaded
media on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wger = import 'github.com/metio/kurly/workloads/wger/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  cnpg(name='wger-db', database='wger'),
  valkey(name='wger-cache'),
  wger(siteUrl='https://wger.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wger` | |
| `image` | `docker.io/wger/server:2.6.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | uploaded media (`/home/wger/media`) |
| `dbHost` / `dbName` / `dbUser` | `wger-db-rw` / `wger` / `wger` | the PostgreSQL database |
| `redisHost` | `wger-cache` | the Redis/valkey Service |
| `siteUrl` | inferred | the public URL |
| `secretName` | `wger-secrets` | Secret with `DJANGO_DB_PASSWORD` and `SECRET_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database, cache, and secrets

wger reads its database and cache coordinates and its `SECRET_KEY` from the
environment. The non-secret coordinates default to a [cnpg-cluster](../cnpg-cluster/)
named `wger-db` and a [valkey](../valkey/) `cache` named `wger-cache`; the sensitive
values (`DJANGO_DB_PASSWORD`, `SECRET_KEY`) come from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `wger-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The all-in-one image runs nginx + uWSGI + Celery and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Uploaded media lives on a ReadWriteOnce
volume, so this is **one replica, recreated**.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-07-31, and observed rolling out.

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
metadata: { name: kurly, namespace: wger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wger, namespace: wger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wger, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wger }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wger, namespace: wger }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wger } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wger, namespace: wger }
spec:
  serviceAccountName: wger-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wger/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wger, importPath: github.com/metio/kurly/workloads/wger }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wger, namespace: wger }
spec:
  serviceAccountName: wger-deployer
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
        name: wger
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wger }
```

<!-- END generated: jaas-deploy -->
