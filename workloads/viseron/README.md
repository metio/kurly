<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# viseron

[Viseron](https://github.com/roflcoopter/viseron) — records network cameras and
runs object detection over the footage, keeping the events worth keeping. A
composable `kurly.http` workload on the official image, with its configuration
and everything it records on one PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local viseron = import 'github.com/metio/kurly/workloads/viseron/server.libsonnet';

kurly.list(viseron())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `viseron` | |
| `image` | `docker.io/roflcoopter/viseron:3.6.0` | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | configuration and footage |
| `puid` / `pgid` | `911` / `911` | own the files on the volume |
| `timezone` | `UTC` | `TZ` |
| `resources` | 500m / 1Gi, limit 4Gi | detection is the expensive half |

## Nothing is recorded until you configure a camera

Viseron is configured entirely from `config.yaml` on the volume. The first start
writes one with no cameras in it, so the server comes up, serves the web UI, and
records nothing. Edit it in the UI (or in the volume) and let Viseron restart.

## Size the volume for retention, not for the application

Recorded video is what fills this volume, and it fills it continuously. The
segments, snapshots, thumbnails and event clips all live on the same claim as
the configuration:

| path | what |
|---|---|
| `/config` | `config.yaml` and Viseron's own database |
| `/segments` | recorded video |
| `/snapshots`, `/thumbnails`, `/event_clips` | what detection produces |

Work out what retention the cameras' config asks for and size `storageSize` from
that; the application itself needs almost none of it.

## Less hardened, deliberately

The s6-overlay init starts as root and drops to the `abc` account named by
`puid`/`pgid`, so the container runs as root with `CHOWN`, `DAC_OVERRIDE`,
`FOWNER`, `SETGID` and `SETUID` granted back by name. The root filesystem is
writable too: s6 supervises nginx, PostgreSQL, go2rtc and Viseron itself from
the image's own tree, and an `emptyDir` over `/run` alone leaves every one of
them failing to exec its own run script. Everything else stays — capabilities
are otherwise dropped, privilege escalation is off, seccomp is on, and ffmpeg's
scratch files go to a bounded `emptyDir` at `/tmp`.

## Probes are connection probes

The web UI is a single-page app whose routes move between releases, and an
`httpGet` probe naming one that has moved answers 404 and restarts the pod
forever. Loading the detector models and opening every camera takes minutes on a
first start, so that budget lives in a startup probe rather than in a longer
liveness delay.

## Persistence

Configuration and footage live on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: viseron }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-viseron, namespace: viseron }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/viseron, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: viseron }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-viseron, namespace: viseron }
spec: { sourceRef: { kind: OCIRepository, name: kurly-viseron } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: viseron, namespace: viseron }
spec:
  serviceAccountName: viseron-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/viseron/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-viseron, importPath: github.com/metio/kurly/workloads/viseron }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: viseron, namespace: viseron }
spec:
  serviceAccountName: viseron-deployer
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
        name: viseron
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: viseron }
```

<!-- END generated: jaas-deploy -->
