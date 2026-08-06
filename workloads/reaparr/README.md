<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# reaparr

[Reaparr](https://github.com/Reaparr/Reaparr) — it connects to the Plex servers
your account has access to, browses their libraries, and copies what you pick
into your own. A plain composable `kurly.http` workload; the SQLite database,
settings and logs live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local reaparr = import 'github.com/metio/kurly/workloads/reaparr/server.libsonnet';

kurly.list(reaparr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `reaparr` | |
| `image` | `reaparr/reaparr:v0.23.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/Config` |
| `timezone` | `UTC` | `TZ` |
| `logLevel` | `INFORMATION` | `LOG_LEVEL` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and its API on `:7000` — compose an exposure onto it.

## Where the media goes

Reaparr downloads into `/Downloads` and moves finished media into `/Movies` and
`/TvShows`. Only `/Config` is persisted here: the other three are ordinary
directories inside the container, so **anything Reaparr fetches is lost with the
pod** until the volumes your library really lives on are mounted over them.
Compose those mounts on before pointing anyone at the instance.

## Credentials

Plex accounts and server tokens are entered in the web UI and stored in the
`/Config` database. There is no environment contract for them, so kurly authors
no Secret — back up the volume instead.

## Hardened as shipped

The image ships `USER abc` and its s6 service execs the application as that
account, so nothing here needs root: the container keeps the read-only root
filesystem, the dropped capabilities and the `restricted` posture. The uid is
pinned to `911` so the volume is group-owned by the account that has to write the
database — an unprivileged init cannot chown it — and `/run`, `/var/run` and
`/tmp` are scratch space for the s6 service tree and the .NET runtime.

Probed by connection rather than by path, and given a startup budget: the first
boot migrates the database before it serves.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: reaparr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-reaparr, namespace: reaparr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/reaparr, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: reaparr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-reaparr, namespace: reaparr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-reaparr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: reaparr, namespace: reaparr }
spec:
  serviceAccountName: reaparr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/reaparr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-reaparr, importPath: github.com/metio/kurly/workloads/reaparr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: reaparr, namespace: reaparr }
spec:
  serviceAccountName: reaparr-deployer
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
        name: reaparr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: reaparr }
```

<!-- END generated: jaas-deploy -->
