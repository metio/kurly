<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# myspeed

[MySpeed](https://github.com/gnmyt/myspeed) — runs speed tests on a schedule and
charts the history, so you can see when a connection degraded rather than only
that it feels slow today. A plain composable `kurly.http` workload keeping its
database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local myspeed = import 'github.com/metio/kurly/workloads/myspeed/server.libsonnet';

kurly.list(myspeed())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `myspeed` | |
| `image` | `germannewsmaker/myspeed:1.0.9` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/myspeed/data` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the dashboard on `:5216`:

```jsonnet
kurly.list([
  myspeed()
  + kurly.expose.ownGateway('speed.example.com', 'istio', tls='myspeed-tls'),
  kurly.certificate('myspeed-tls', ['speed.example.com'], 'letsencrypt-prod'),
])
```

## What it measures here

Run from a cluster, this measures **the node's path to the internet** — not a home
connection. The same caveat as [speedtest-tracker](../speedtest-tracker/), and
worth settling before you read the graphs.

## Two writable paths, not one

MySpeed creates `data`, `bin`, `data/logs` and `data/servers` **relative to its
working directory** on every start, and downloads the speedtest CLI into `bin`. So
`/myspeed/bin` is ephemeral scratch alongside the data volume.

Without it the container exits with a single line:

```text
Could not create the data folder. Please check the permission
```

— which names the one directory that was fine. The failing one is `bin`.

## Persistence

One database on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled). `bin` is deliberately not persisted: it holds a downloaded binary
that is fetched again on start.

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
metadata: { name: kurly, namespace: myspeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-myspeed, namespace: myspeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/myspeed, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: myspeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-myspeed, namespace: myspeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly-myspeed } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: myspeed, namespace: myspeed }
spec:
  serviceAccountName: myspeed-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/myspeed/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-myspeed, importPath: github.com/metio/kurly/workloads/myspeed }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: myspeed, namespace: myspeed }
spec:
  serviceAccountName: myspeed-deployer
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
        name: myspeed
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: myspeed }
```

<!-- END generated: jaas-deploy -->
