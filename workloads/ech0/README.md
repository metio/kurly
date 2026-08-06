<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ech0

[Ech0](https://github.com/lin-snow/Ech0) — a lightweight publishing platform for
short posts, with federation between instances. A plain composable `kurly.http`
workload keeping its SQLite database and uploaded media on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ech0 = import 'github.com/metio/kurly/workloads/ech0/server.libsonnet';

kurly.list(ech0())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ech0` | |
| `image` | `docker.io/sn0wl1n/ech0:v5.5.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/app/data` |
| `secretName` | `ech0` | supplies `JWT_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

## The Secret

`JWT_SECRET` signs the tokens users hold, and the published run command carries a
documented value for it — an instance left with that is one anybody can mint an
administrator token for. kurly authors no Secret; supply one and it is read via
`envFrom`:

```shell
kubectl create secret generic ech0 \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Persistence

The SQLite database and locally stored media both live under `/app/data` on a
ReadWriteOnce volume, so this is **one replica, recreated** (never rolled).
Pointing Ech0 at S3 object storage from its own settings moves the media out but
not the database, so the volume stays.

## Probes

Ech0 answers the web app on `/`, but the probes here are connection probes: what a
readiness check needs to know is that the listener is up, and asking for a page
turns any future redirect or authentication gate into a pod that never becomes
ready.

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
metadata: { name: kurly, namespace: ech0 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ech0, namespace: ech0 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ech0, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ech0 }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ech0, namespace: ech0 }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ech0 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ech0, namespace: ech0 }
spec:
  serviceAccountName: ech0-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ech0/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ech0, importPath: github.com/metio/kurly/workloads/ech0 }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ech0, namespace: ech0 }
spec:
  serviceAccountName: ech0-deployer
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
        name: ech0
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ech0 }
```

<!-- END generated: jaas-deploy -->
