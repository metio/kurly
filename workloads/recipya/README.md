<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# recipya

[Recipya](https://github.com/reaper47/recipya) — a recipe manager: import recipes
from a website or a photo, plan meals for the week and turn the plan into a
shopping list. A plain composable `kurly.http` workload keeping its SQLite
databases, images and videos on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local recipya = import 'github.com/metio/kurly/workloads/recipya/server.libsonnet';

kurly.list(recipya())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `recipya` | |
| `image` | `docker.io/reaper99/recipya:v1.2.2` | |
| `port` | `8078` | container port, Service port and `RECIPYA_SERVER_PORT` |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data` |
| `baseUrl` | unset | the URL browsers reach this instance at |
| `noSignups` | `false` | refuse new registrations |
| `env` / `resources` / `labels` / `annotations` | | |

## The port is not the image's `EXPOSE`

The image still exposes 8080; Recipya listens on whatever `RECIPYA_SERVER_PORT`
names and has **no default of its own** — unset, it binds port 0. The `port`
parameter sets the environment variable, the container port and the Service port
together, so the three cannot drift apart.

## First boot reaches the internet, and exits if it cannot

Recipya downloads a 62 MB nutrition database (FDC) from githubusercontent into its
data directory the first time it starts, and terminates the process when that
download fails. A NetworkPolicy composed onto this workload has to allow egress —
at least until the file is on the volume:

```jsonnet
recipya() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443] }])
```

That download also happens before anything listens, which is what the startup
probe's generous budget is for.

## The empty directory at `/.dockerenv`

Recipya decides whether to read its configuration from the environment or to write
a `config.json` by asking whether `/.dockerenv` exists. Under Kubernetes it does
not, so the app takes the interactive path, gets EOF on every prompt, accepts the
defaults — and one of those defaults binds a **random ephemeral port**, which it
then persists into the config file. Mounting an empty directory at that path makes
the `stat` succeed and keeps the app on its documented environment-variable
configuration.

## Persistence

SQLite, uploaded images and videos live under `/data` on a ReadWriteOnce volume,
so this is **one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: recipya }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-recipya, namespace: recipya }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/recipya, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: recipya }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-recipya, namespace: recipya }
spec: { sourceRef: { kind: OCIRepository, name: kurly-recipya } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: recipya, namespace: recipya }
spec:
  serviceAccountName: recipya-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/recipya/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-recipya, importPath: github.com/metio/kurly/workloads/recipya }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: recipya, namespace: recipya }
spec:
  serviceAccountName: recipya-deployer
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
        name: recipya
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: recipya }
```

<!-- END generated: jaas-deploy -->
