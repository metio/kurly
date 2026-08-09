<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lyrion-music-server

[Lyrion Music Server](https://lyrion.org/) — the music server formerly known as
Logitech Media Server: it indexes a music library and streams it to Squeezebox
hardware, software players and mobile clients. A plain composable `kurly.http`
workload on the official image: its preferences, cache and scanned database live on
a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lyrion = import 'github.com/metio/kurly/workloads/lyrion-music-server/server.libsonnet';

kurly.list(lyrion())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `lyrion-music-server` | |
| `image` | `docker.io/lmscommunity/lyrionmusicserver:9.2.0` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | server data (`/config`), music (`/music`), playlists (`/playlist`) |
| `puid` / `pgid` | `1000` / `1000` | the user the server drops to, and the owner of the mounted files |
| `timezone` | `UTC` | |
| `env` | `{}` | extra settings, e.g. `EXTRA_ARGS` |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and JSON-RPC API on `:9000` — compose an exposure onto it. Put your
music under `/music` on the volume.

## Players

Hardware and software players speak slimproto on `:3483` (TCP, plus UDP for
discovery) and the telnet CLI listens on `:9090`; all three are published on the
Service beside the web port. Route them with a NodePort or a dedicated LoadBalancer
so players on the LAN can reach the server — the web UI works without them.

## Security

The entrypoint starts as root to renumber its own user to `puid`/`pgid`, chown
`/config` and `/playlist`, and then drop to that user. So this runs as root with a
writable root filesystem (`usermod` rewrites `/etc/passwd`) and the capabilities `su`
needs, while kurly keeps the rest of the hardening — seccomp, user namespaces,
resource limits, no service account token.

## Persistence

Preferences, cache and the scanned database live on a ReadWriteOnce volume, so this
is **one replica, recreated** — the same single-writer discipline as
[navidrome](../navidrome/).

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
metadata: { name: kurly, namespace: lyrion-music-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lyrion-music-server, namespace: lyrion-music-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lyrion-music-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lyrion-music-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lyrion-music-server, namespace: lyrion-music-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lyrion-music-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lyrion-music-server, namespace: lyrion-music-server }
spec:
  serviceAccountName: lyrion-music-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lyrion-music-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lyrion-music-server, importPath: github.com/metio/kurly/workloads/lyrion-music-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lyrion-music-server, namespace: lyrion-music-server }
spec:
  serviceAccountName: lyrion-music-server-deployer
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
        name: lyrion-music-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lyrion-music-server }
```

<!-- END generated: jaas-deploy -->
