<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vanilla-cookbook

[Vanilla Cookbook](https://github.com/jt196/vanilla-cookbook) — a recipe manager
that imports recipes from other cookbook applications and from the web. A plain
composable `kurly.http` workload on the official image, keeping its SQLite database
and its uploaded images on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cookbook = import 'github.com/metio/kurly/workloads/vanilla-cookbook/server.libsonnet';

kurly.list(cookbook(origin='https://recipes.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vanilla-cookbook` | |
| `image` | `docker.io/jt196/vanilla-cookbook:stable` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite database (`/app/prisma/db`) |
| `uploadsSize` | `5Gi` | uploaded images and imports (`/app/uploads`) |
| `origin` | `http://localhost:3000` | the public URL the app is reached at |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## ORIGIN

`ORIGIN` is the one setting the application cannot infer. SvelteKit checks it
against the request when a form is submitted, so a wrong value turns every login
and every save into a rejected cross-site request while the pages themselves still
render. The default is a localhost URL so a default render boots — point it at the
real host for a real deployment.

## Persistence

Two volumes, because the application keeps its data in two places and a single
mount would leave one of them on the container filesystem: the SQLite database
under `/app/prisma/db`, and uploaded recipe images and import files under
`/app/uploads`. Both are ReadWriteOnce, so this is **one replica, recreated**.

## Security posture

The container runs as root with a writable root filesystem and its capabilities
kept. The entrypoint creates the data directories, aligns the application user with
`PUID`/`PGID`, chowns both volumes before handing over to that user with `gosu`, and
starts a cron daemon for the scheduled database backup — none of which works as an
unprivileged user on a read-only filesystem, and the entrypoint fails the container
rather than continuing.

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
metadata: { name: kurly, namespace: vanilla-cookbook }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vanilla-cookbook, namespace: vanilla-cookbook }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vanilla-cookbook, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vanilla-cookbook }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vanilla-cookbook, namespace: vanilla-cookbook }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vanilla-cookbook } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vanilla-cookbook, namespace: vanilla-cookbook }
spec:
  serviceAccountName: vanilla-cookbook-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vanilla-cookbook/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vanilla-cookbook, importPath: github.com/metio/kurly/workloads/vanilla-cookbook }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vanilla-cookbook, namespace: vanilla-cookbook }
spec:
  serviceAccountName: vanilla-cookbook-deployer
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
        name: vanilla-cookbook
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vanilla-cookbook }
```

<!-- END generated: jaas-deploy -->
