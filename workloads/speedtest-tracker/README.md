<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# speedtest-tracker

[Speedtest Tracker](https://github.com/alexjustesen/speedtest-tracker) — runs
internet speed tests on a schedule and keeps the history: download, upload and
latency over time, with charts and alerting. A plain composable `kurly.http`
workload whose SQLite database lives on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local speedtestTracker = import 'github.com/metio/kurly/workloads/speedtest-tracker/server.libsonnet';

kurly.list(speedtestTracker(appUrl='https://speedtest.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `speedtest-tracker` | |
| `image` | `ghcr.io/alexjustesen/speedtest-tracker:v0.19.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/config` |
| `appUrl` | unset | the public URL |
| `secretName` | `speedtest-tracker` | supplies `APP_KEY` |
| `env` / `resources` / `labels` / `annotations` | | |

## What it actually measures here

Run from a cluster, this measures **the node's path to the internet** — its uplink
and whatever egress or NAT sits in front of it. That is a useful thing to watch,
and it is not the home-connection number most people install this for. Worth
knowing before you read the graphs.

## The init container creates the database

Laravel *opens* the SQLite file; it does not create it, and neither does this
image. On a fresh volume the result is a container that starts, migrates nothing,
and is torn down by its own s6 supervisor — with the real reason several lines
above the line that stops it:

```text
Database file at path [/config/database.sqlite] does not exist.
...
s6-rc: warning: unable to start service laravel-automations: command exited 1
prog: fatal: stopping the container.
```

So an init container creates the empty file, guarded by `test -f` so it can never
truncate a database that already holds history.

## Less hardened, deliberately

This is an s6-overlay image: the init runs as root, prepares `/config` for the app
account and drops to it, with no path through as an unprivileged process. So root,
the capabilities the drop needs, and the escalation that permits it are all
required — and the root filesystem is writable, because Laravel writes its compiled
configuration and its `.env` beside its own code.

`APP_KEY` still comes from the Secret: the entrypoint writes a fresh one into that
`.env` when none is set, and since the file is not on the volume, every restart
would otherwise mint a new key and orphan what the old one encrypted.

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
metadata: { name: kurly, namespace: speedtest-tracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-speedtest-tracker, namespace: speedtest-tracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/speedtest-tracker, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: speedtest-tracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-speedtest-tracker, namespace: speedtest-tracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly-speedtest-tracker } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: speedtest-tracker, namespace: speedtest-tracker }
spec:
  serviceAccountName: speedtest-tracker-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/speedtest-tracker/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-speedtest-tracker, importPath: github.com/metio/kurly/workloads/speedtest-tracker }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: speedtest-tracker, namespace: speedtest-tracker }
spec:
  serviceAccountName: speedtest-tracker-deployer
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
        name: speedtest-tracker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: speedtest-tracker }
```

<!-- END generated: jaas-deploy -->
