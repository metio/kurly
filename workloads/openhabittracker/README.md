<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openhabittracker

[OpenHabitTracker](https://github.com/Jinjinov/OpenHabitTracker) — habits, tasks
and notes in one place, with time tracking, a calendar view and completion
statistics. A plain composable `kurly.http` workload; the database lives on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openhabittracker = import 'github.com/metio/kurly/workloads/openhabittracker/server.libsonnet';

kurly.list(openhabittracker())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `openhabittracker` | |
| `image` | `jinjinov/openhabittracker:1.2.3` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | `/app/.OpenHabitTracker` |
| `secretName` | `openhabittracker` | the account and the JWT key |
| `env` / `resources` / `labels` / `annotations` | | |

## One instance, one user

The published image is a Blazor Server build for **exactly one user**. The
account is whatever the Secret says; there is no registration page and no second
account to add. Run one instance per person rather than looking for the user
management — there is none.

The Secret holds:

| Key | |
|---|---|
| `APPSETTINGS_USERNAME` | the account name |
| `APPSETTINGS_EMAIL` | the account address |
| `APPSETTINGS_PASSWORD` | its password |
| `APPSETTINGS_JWT_SECRET` | signs the session tokens |

kurly authors no Secret itself. Without one the instance has no account to log
in with.

## Single writer

One database file on a ReadWriteOnce volume: one replica, `Recreate` rather than
a rolling update. A second pod would sit Pending behind the volume anyway.

## Less hardened, deliberately

The request logger opens its own LiteDB file at `/app/watchlogs.db` — inside the
install tree, beside the assemblies, so no `emptyDir` can be mounted over it
without hiding the application. The file is opened on the **first request**, not
at startup, so a read-only root filesystem here does not fail the pod: it starts,
reports healthy, and then fails every request it is asked to serve. The workload
therefore runs with a writable root filesystem.

The image declares `APP_UID=1654` and creates the matching account but never
switches to it, and the install tree it writes into is owned by root — running as
the account the image names denies those writes. So this workload runs as root.
Everything else about the hardened posture stands.

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
metadata: { name: kurly, namespace: openhabittracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-openhabittracker, namespace: openhabittracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/openhabittracker, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: openhabittracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-openhabittracker, namespace: openhabittracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly-openhabittracker } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: openhabittracker, namespace: openhabittracker }
spec:
  serviceAccountName: openhabittracker-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/openhabittracker/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-openhabittracker, importPath: github.com/metio/kurly/workloads/openhabittracker }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: openhabittracker, namespace: openhabittracker }
spec:
  serviceAccountName: openhabittracker-deployer
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
        name: openhabittracker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: openhabittracker }
```

<!-- END generated: jaas-deploy -->
