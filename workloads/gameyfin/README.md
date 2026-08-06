<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gameyfin

[Gameyfin](https://gameyfin.org) — a game library manager: it scans directories
of games, enriches them with metadata and cover art, and serves the result as a
browsable web library your users can download from. A plain composable
`kurly.http` workload keeping its H2 database and stored content on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gameyfin = import 'github.com/metio/kurly/workloads/gameyfin/server.libsonnet';

kurly.list(gameyfin())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gameyfin` | |
| `image` | `docker.io/grimsi/gameyfin:2.1.2` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/opt/gameyfin/data`, with `db` and `logs` as subpaths |
| `puid` / `pgid` | `1000` / `1000` | who owns the files the entrypoint hands over |
| `secretName` | `gameyfin` | supplies `APP_KEY` |
| `env` / `resources` / `labels` / `annotations` | | |

## APP_KEY is not optional

Gameyfin encrypts the credentials it stores with an AES key read from `APP_KEY`,
and it **exits on startup** when that variable is missing — it generates nothing
for you. The Secret is base64 of 16, 24 or 32 random bytes:

```shell
kubectl create secret generic gameyfin --from-literal=APP_KEY="$(head -c 32 /dev/urandom | base64 -w0)"
```

Rotating it makes everything already encrypted unreadable.

## The games are not on this volume

The volume holds Gameyfin's own state — the H2 database, the content it stores
for a game, its logs. The **games themselves** live wherever you already keep
them, and Gameyfin scans library directories an operator configures through the
web interface after the first start. Either put them under the volume this
workload already owns (`/opt/gameyfin/data/games` needs no extra manifest at
all), or attach the claim they really live on:

```jsonnet
gameyfin() + {
  deployment+: { spec+: { template+: { spec+: {
    volumes+: [{ name: 'games', persistentVolumeClaim: { claimName: 'games', readOnly: true } }],
    containers: [
      c { volumeMounts+: [{ name: 'games', mountPath: '/games', readOnly: true }] }
      for c in super.containers
    ],
  } } } },
}
```

A read-only mount is enough unless you upload through Gameyfin.

## Two ports, one of them private

Gameyfin is a Spring Boot application and publishes its management endpoints —
`health`, `metrics`, `prometheus`, and a `restart` endpoint that needs no
authentication — on a **separate port, 8081**. That port is deliberately not in
the Service: nothing outside the pod has any business reaching a restart
endpoint. Scrape it with a sidecar or an extra port if you want the metrics, but
do not route to it. The web app and API are on `:8080`, which is what an exposure
attaches to.

The probes deliberately do **not** use `/actuator/health`: it reports DOWN — and
answers 500 — while the library is still unconfigured, which is exactly the state
a fresh install is in, so a pod that came up perfectly would be killed forever.
They are connection probes on `:8080` instead.

## Root, briefly

The entrypoint aligns the `gameyfin` account to `PUID`/`PGID`, chowns
`/opt/gameyfin` and then `su-exec`s the JVM, so the container starts as root with
a writable root filesystem and five named capabilities. The application itself
never runs as root; everything kurly hardens beyond that — dropped capabilities,
seccomp, no privilege escalation — stays in place.

## First start is slow

A JVM, a Vaadin front end and the Flyway migrations against a fresh H2 database
take a while, and nothing listens until they are done — hence the startup probe
with a generous budget rather than a stretched liveness delay.

## Single writer

One H2 database on a ReadWriteOnce volume: one replica, recreated rather than
rolled, so two pods never hold the database at once.

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
metadata: { name: kurly, namespace: gameyfin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gameyfin, namespace: gameyfin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gameyfin, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gameyfin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gameyfin, namespace: gameyfin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gameyfin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gameyfin, namespace: gameyfin }
spec:
  serviceAccountName: gameyfin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gameyfin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gameyfin, importPath: github.com/metio/kurly/workloads/gameyfin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gameyfin, namespace: gameyfin }
spec:
  serviceAccountName: gameyfin-deployer
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
        name: gameyfin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gameyfin }
```

<!-- END generated: jaas-deploy -->
