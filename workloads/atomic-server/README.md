<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# atomic-server

[AtomicServer](https://github.com/atomicdata-dev/atomic-server) — a graph
database with documents, collections, full-text search and a browser UI, all in
one static binary. A plain composable `kurly.http` workload; the store, the
uploads and the search index live on one PersistentVolume, so it needs nothing
external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local atomicServer = import 'github.com/metio/kurly/workloads/atomic-server/server.libsonnet';

kurly.list(atomicServer(serverUrl='https://atomic.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `atomic-server` | |
| `image` | `joepmeneer/atomic-server:v0.38.0` | |
| `port` | `9883` | upstream's own default, not the image's `80` |
| `serverUrl` | unset | the absolute URL this instance is reached at |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/atomic-storage` |
| `env` / `resources` / `labels` / `annotations` | | |

## Set `serverUrl` before anybody writes data

Every resource AtomicServer stores is identified by an absolute URL derived from
this value. Changing it later does not rename the resources already stored — it
leaves them addressed under a hostname that no longer serves them. Unset, the
server calls itself `http://localhost:9883`, which is right for a smoke test and
wrong for anything reachable.

## Claim `/setup` immediately

The first visitor to `/setup` becomes the root agent, and until somebody goes
there the invite is unclaimed. On an exposed instance that is whoever arrives
first, so claim it right after the first deploy — or compose the exposure only
once you have. Keep the private key it hands you; there is no second copy.

## The port is moved off the image's default

The image sets `ATOMIC_PORT=80`, which only a process holding `NET_BIND_SERVICE`
may bind. This workload runs the binary on upstream's own default `9883` as an
ordinary user instead, so the pod keeps the hardened posture.

## Persistence

One embedded store on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). Two servers writing one store is not something the
store sorts out afterwards.

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
metadata: { name: kurly, namespace: atomic-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-atomic-server, namespace: atomic-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/atomic-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: atomic-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-atomic-server, namespace: atomic-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-atomic-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: atomic-server, namespace: atomic-server }
spec:
  serviceAccountName: atomic-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/atomic-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-atomic-server, importPath: github.com/metio/kurly/workloads/atomic-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: atomic-server, namespace: atomic-server }
spec:
  serviceAccountName: atomic-server-deployer
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
        name: atomic-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: atomic-server }
```

<!-- END generated: jaas-deploy -->
