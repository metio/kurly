<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wbo

[WBO](https://github.com/lovasoa/whitebophir) — a collaborative whiteboard. Open a
board URL, draw, and everyone else on that URL sees it as you draw. A plain
composable `kurly.http` workload; boards are saved as files on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wbo = import 'github.com/metio/kurly/workloads/wbo/server.libsonnet';

kurly.list(wbo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wbo` | |
| `image` | `lovasoa/wbo:v2.9.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/opt/app/server-data` |
| `env` / `resources` / `labels` / `annotations` | | |

## The URL is the credential

WBO has **no accounts and no per-board permissions**. Anyone who knows a board's
URL can read and draw on it, and board names are guessable — so an instance
reachable from the internet is a whiteboard for the internet.

That may be exactly what you want for a public sketchpad. If it is not, put an
authenticating proxy in front of it; there is nothing inside WBO to configure.

## Expose it with something that keeps connections open

Drawing is streamed over a socket. A proxy with a short idle timeout produces the
confusing failure rather than an obvious one: the board still loads, still looks
connected, and simply stops showing other people's strokes.

## Binding :80 without root

The image already selects uid 1000 and then asks it to bind `:80`, which an
unprivileged process may not do. Rather than run the whole server as root for one
port, this grants back the single capability binding needs:

```jsonnet
+ kurly.runAs(1000, gid=1000, fsGroup=1000)
+ kurly.addCapabilities(['NET_BIND_SERVICE'])
```

Everything else stays dropped.

## Persistence

Boards are files on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled) — and that is not only about the volume: two pods would each hold
their own half of a live drawing session, so people on the same board would not
see each other.

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
metadata: { name: kurly, namespace: wbo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wbo, namespace: wbo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wbo, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wbo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wbo, namespace: wbo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wbo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wbo, namespace: wbo }
spec:
  serviceAccountName: wbo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wbo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wbo, importPath: github.com/metio/kurly/workloads/wbo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wbo, namespace: wbo }
spec:
  serviceAccountName: wbo-deployer
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
        name: wbo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wbo }
```

<!-- END generated: jaas-deploy -->
