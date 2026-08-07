<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# memtly

[Memtly](https://github.com/Memtly/Memtly.Community) — event photo sharing: guests
scan a QR code, see the gallery and upload their own photos and videos, for a
wedding, a concert or a trip. A plain composable `kurly.http` workload keeping its
SQLite database, uploads, thumbnails and branding on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local memtly = import 'github.com/metio/kurly/workloads/memtly/server.libsonnet';

kurly.list(memtly())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `memtly` | |
| `image` | `docker.io/memtly/memtly:1.0.5.3` | |
| `title` | `Memtly` | header and browser tab |
| `baseUrl` | none | the public URL put into links and QR codes |
| `forceHttps` | `false` | see below |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/uploads` |
| `configStorageSize` | `1Gi` | `/app/config` — the SQLite database and settings |
| `thumbnailStorageSize` | `5Gi` | `/app/thumbnails` |
| `resourceStorageSize` | `1Gi` | `/app/custom_resources` |
| `secretName` | `memtly` | `ENCRYPTION_KEY`, `ENCRYPTION_SALT`, `ACCOUNT_ADMIN_PASSWORD` |
| `env` / `resources` / `labels` / `annotations` | | |

## The Secret is not hardening

All three keys ship with published defaults in the project's own compose file —
`ChangeMe`, `ChangeMe` and `admin`. The encryption key protects what Memtly stores
encrypted and the admin password is the way into every gallery, so supplying the
Secret is the difference between a private gallery and a public one.

## `forceHttps` and the redirect

Memtly redirects http to https itself, and does so by default. Behind an ingress
that terminates TLS the pod only ever sees http, so leaving it on sends every
request back to a URL the ingress has already served. This workload therefore
defaults it off; turn it on where the pod is reached over https directly.

The probes are by connection for the same reason: every page redirects, to the
login, the gallery selector or to https.

## Settings are read once

Memtly imports the environment at its **first** boot and is administered from its
settings tab afterwards — changing an environment variable on a gallery that has
already started will not move the setting. The upstream image also reports errors
to a Graylog endpoint the project runs; that switch lives in the settings tab.

## Persistence

A SQLite file and an upload directory on ReadWriteOnce volumes, so this is **one
replica, recreated** (never rolled). `DATABASE_TYPE` and
`DATABASE_CONNECTION_STRING` through `env` move the data to an external MariaDB,
MySQL, PostgreSQL or SQL Server; the uploads stay on the volume either way.

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
metadata: { name: kurly, namespace: memtly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-memtly, namespace: memtly }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/memtly, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: memtly }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-memtly, namespace: memtly }
spec: { sourceRef: { kind: OCIRepository, name: kurly-memtly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: memtly, namespace: memtly }
spec:
  serviceAccountName: memtly-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/memtly/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-memtly, importPath: github.com/metio/kurly/workloads/memtly }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: memtly, namespace: memtly }
spec:
  serviceAccountName: memtly-deployer
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
        name: memtly
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: memtly }
```

<!-- END generated: jaas-deploy -->
