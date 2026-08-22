<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# trailbase

[TrailBase](https://trailbase.io) — a single-executable application backend: a
SQLite database with type-safe REST and realtime APIs, authentication, a
WebAssembly runtime and an admin UI, all in one process. A plain composable
`kurly.http` workload keeping its whole state in one data directory on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local trailbase = import 'github.com/metio/kurly/workloads/trailbase/server.libsonnet';

kurly.list(trailbase())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `trailbase` | |
| `image` | `docker.io/trailbase/trailbase:0.33.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/app/traildepot` |
| `env` / `resources` / `labels` / `annotations` | | |

## Everything is in the data directory

The database, the configuration, the auth keys that sign users' tokens and any
uploaded files all live under `/app/traildepot`, which is the volume. Back that
up and you have backed up the deployment; lose it and every account goes with it.
There is nothing else to keep.

The volume is mounted **at the directory the image's own command names**, which
is what upstream's compose file does too. That masks the WebAssembly components
the image ships underneath it, so a deployment that runs components supplies them
into the volume rather than expecting the image's copies to still be visible.

## The first administrator

TrailBase initialises a fresh data directory on first start and prints the
administrator's credentials to the log. Read them there and change the password
in the admin UI at `/_/admin` — the workload mints no Secret, because the
application creates the account itself:

```shell
kubectl logs deploy/trailbase | head
```

## Configuration is environment, and the port is fixed

The command in the image binds `0.0.0.0:4000` and the stage declares the same
port. `env` passes anything else the process reads. Because the Service is named
after the workload, Kubernetes would otherwise inject `TRAILBASE_PORT` as a
`tcp://` URL into that same environment, so service links are switched off.

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
metadata: { name: kurly, namespace: trailbase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-trailbase, namespace: trailbase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/trailbase, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: trailbase }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-trailbase, namespace: trailbase }
spec: { sourceRef: { kind: OCIRepository, name: kurly-trailbase } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: trailbase, namespace: trailbase }
spec:
  serviceAccountName: trailbase-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/trailbase/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-trailbase, importPath: github.com/metio/kurly/workloads/trailbase }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: trailbase, namespace: trailbase }
spec:
  serviceAccountName: trailbase-deployer
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
        name: trailbase
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: trailbase }
```

<!-- END generated: jaas-deploy -->
