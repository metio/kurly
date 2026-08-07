<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wavelog

[Wavelog](https://github.com/wavelog/wavelog) — a web logbook for radio amateurs:
contacts, awards, statistics and maps. A plain composable `kurly.http` workload on
the official image, backed by an external MySQL/MariaDB, with its generated
configuration, uploads and user data on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wavelog = import 'github.com/metio/kurly/workloads/wavelog/server.libsonnet';

kurly.list(wavelog())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wavelog` | |
| `image` | `ghcr.io/wavelog/wavelog:latest` | |
| `configSize` | `1Gi` | the installer's output (`/var/www/html/application/config/docker`) |
| `uploadSize` | `5Gi` | QSL cards and ADIF imports (`/var/www/html/uploads`) |
| `userdataSize` | `5Gi` | per-user data (`/var/www/html/userdata`) |
| `storageClass` | cluster default | |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and first run

Wavelog needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. It takes **no database coordinates from the environment**:
the web installer at `/install` asks for them once and writes them into
`application/config/docker`, which is why that directory is a volume of its own —
lose it and the instance is back at the install wizard. There is nothing for a
consumer to mint, so this workload reads **no Secret**.

## Security and persistence

The Apache + PHP image's entrypoint runs as **root** (it renders a `php.ini`
fragment, drops the install lock, and chowns the writable directories) and Apache
binds `:80`, so this workload relaxes kurly's non-root and read-only-rootfs
defaults. The volumes are ReadWriteOnce, so this is **one replica, recreated**.
Both probes are connection probes: an unconfigured instance redirects to `/install`
and a configured one to the login page, so no path answers 200 in both states.

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
metadata: { name: kurly, namespace: wavelog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wavelog, namespace: wavelog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wavelog, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wavelog }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wavelog, namespace: wavelog }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wavelog } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wavelog, namespace: wavelog }
spec:
  serviceAccountName: wavelog-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wavelog/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wavelog, importPath: github.com/metio/kurly/workloads/wavelog }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wavelog, namespace: wavelog }
spec:
  serviceAccountName: wavelog-deployer
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
        name: wavelog
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wavelog }
```

<!-- END generated: jaas-deploy -->
