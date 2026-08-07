<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# actualbudget

[Actual Budget](https://github.com/actualbudget/actual) — a local-first personal
finance and budgeting app. A plain composable `kurly.http` workload that keeps its
budgets and sync state in a SQLite database on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local actual = import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet';

kurly.list(actual())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `actualbudget` | |
| `image` | `docker.io/actualbudget/actual-server:26.8.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web app and sync API on `:5006` — compose an exposure onto it:

```jsonnet
kurly.list([
  actual()
  + kurly.expose.ownGateway('budget.example.com', 'istio', tls='actual-tls'),
  kurly.certificate('actual-tls', ['budget.example.com'], 'letsencrypt-prod'),
])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) to keep two pods off the file — the same single-writer discipline as
[vaultwarden](../vaultwarden/).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-07-30, and observed rolling out.

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
metadata: { name: kurly, namespace: actualbudget }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-actualbudget, namespace: actualbudget }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/actualbudget, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: actualbudget }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-actualbudget, namespace: actualbudget }
spec: { sourceRef: { kind: OCIRepository, name: kurly-actualbudget } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: actualbudget, namespace: actualbudget }
spec:
  serviceAccountName: actualbudget-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-actualbudget, importPath: github.com/metio/kurly/workloads/actualbudget }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: actualbudget, namespace: actualbudget }
spec:
  serviceAccountName: actualbudget-deployer
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
        name: actualbudget
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: actualbudget }
```

<!-- END generated: jaas-deploy -->
