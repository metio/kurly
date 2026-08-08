<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sentryshot

[SentryShot](https://codeberg.org/SentryShot/sentryshot) — a network video
recorder for IP cameras: full-resolution live view, 24/7 recording, and
TFlite object detection. A plain composable `kurly.http` workload on the
official image: cameras, accounts and the recording index live on one
PersistentVolume and the recordings themselves on another, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sentryshot = import 'github.com/metio/kurly/workloads/sentryshot/server.libsonnet';

kurly.list(sentryshot())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sentryshot` | |
| `image` | `codeberg.org/sentryshot/sentryshot:v0.3.11` | |
| `auth` | `basic` | `basic` or `none` — see below |
| `maxDiskUsageGb` | `100` | recordings are deleted before this is exceeded |
| `config` | generated | the whole `sentryshot.toml`, if you want your own |
| `configSize` / `storageSize` | `1Gi` / `100Gi` | `/app/configs` and `/app/storage` |
| `storageClass` | cluster default | |
| `env` | `{}` | extra environment — `TZ` is the useful one |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:2020`, with the live view at `/live` — compose an
exposure onto it.

## Configuration

`sentryshot.toml` is read at start and never edited by the app, so it rides
read-only over the `/app/configs` volume as a single file, leaving `accounts.json`
and the monitor definitions on the volume beside it writable. The generated
default pins the paths to the mounts this recipe makes and leaves the motion,
object-detection, thumbnail and MQTT plugins off; pass `config` to enable them.
Cameras are added in the UI, not here.

Keep `maxDiskUsageGb` below `storageSize`: it is the limit SentryShot prunes
recordings against, and a volume that fills before it is reached stops the
recorder rather than the oldest clip.

## Accounts

`auth_basic` starts with an **empty** account list, and there is no command that
seeds one — so a fresh instance with basic auth has nobody who can log in. Deploy
once with `auth='none'` behind an exposure only you can reach, create the admin
account in the UI, then set `auth='basic'` and redeploy; the accounts survive on
the volume.

## Persistence

Both volumes are ReadWriteOnce, so this is **one replica, recreated** — the same
single-writer discipline as [frigate](../frigate/).

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
metadata: { name: kurly, namespace: sentryshot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sentryshot, namespace: sentryshot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sentryshot, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sentryshot }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sentryshot, namespace: sentryshot }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sentryshot } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sentryshot, namespace: sentryshot }
spec:
  serviceAccountName: sentryshot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sentryshot/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sentryshot, importPath: github.com/metio/kurly/workloads/sentryshot }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sentryshot, namespace: sentryshot }
spec:
  serviceAccountName: sentryshot-deployer
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
        name: sentryshot
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sentryshot }
```

<!-- END generated: jaas-deploy -->
