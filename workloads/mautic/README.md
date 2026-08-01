<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mautic

[Mautic](https://github.com/mautic/mautic) — open-source marketing automation. A
plain composable `kurly.http` workload on the official Apache image, backed by an
external MySQL/MariaDB, with its configuration and uploaded media on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mautic = import 'github.com/metio/kurly/workloads/mautic/server.libsonnet';

kurly.list(mautic(siteUrl='https://mautic.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mautic` | |
| `image` | `docker.io/mautic/mautic:7.1.3-apache` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | config + media |
| `dbHost` / `dbName` / `dbUser` | `mautic-db` / `mautic` / `mautic` | the MySQL/MariaDB database |
| `siteUrl` | inferred | the public URL |
| `secretName` | `mautic-secrets` | Secret with `MAUTIC_DB_PASSWORD` (envFrom) |
| `runCronJobs` | `true` | run Mautic's background jobs in-container |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

Mautic needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe — bring your
own and point `dbHost` at it. It reads `MAUTIC_DB_HOST`, `MAUTIC_DB_NAME`,
`MAUTIC_DB_USER` from env and `MAUTIC_DB_PASSWORD` from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `mautic-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities
and no privilege escalation. Configuration and media live on a ReadWriteOnce
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
metadata: { name: kurly, namespace: mautic }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mautic, namespace: mautic }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mautic, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mautic }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mautic, namespace: mautic }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mautic } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mautic, namespace: mautic }
spec:
  serviceAccountName: mautic-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mautic/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mautic, importPath: github.com/metio/kurly/workloads/mautic }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mautic, namespace: mautic }
spec:
  serviceAccountName: mautic-deployer
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
        name: mautic
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mautic }
```

<!-- END generated: jaas-deploy -->
