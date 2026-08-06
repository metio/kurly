<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gerbera

[Gerbera](https://github.com/gerbera/gerbera) — a DLNA media server that
streams a personal library to televisions, players and phones. A plain composable
`kurly.http` workload on the official image: it keeps `config.xml` and its SQLite
database on a PersistentVolume and reads the library from the same volume, so it
needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gerbera = import 'github.com/metio/kurly/workloads/gerbera/server.libsonnet';

kurly.list(gerbera())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gerbera` | |
| `image` | `docker.io/gerbera/gerbera:3.2.1` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | config and database (`/var/run/gerbera`) and media (`/content`) |
| `env` | `{}` | extra settings for the entrypoint |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and the DLNA HTTP endpoints on `:49494` — compose an exposure
onto it. Put your media under `/content` on the volume; the config the entrypoint
generates on first start autoscans that directory with inotify.

## Discovery

Gerbera announces itself with SSDP, which is multicast on `1900/udp` and does not
cross a pod network: players on the LAN will not find this instance by themselves.
Point them at the exposed address instead, or run the pod on the host network —
that is a deployment decision, so the workload does not make it for you.

## Privileges

The image's entrypoint writes the initial config, chowns the volume and then drops
to its own account with `su-exec`, so the container starts as root with `CHOWN`,
`FOWNER`, `SETGID` and `SETUID` granted back on top of the dropped-all default.
The server process itself does not run as root.

## Persistence

Config and database live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as
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
metadata: { name: kurly, namespace: gerbera }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gerbera, namespace: gerbera }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gerbera, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gerbera }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gerbera, namespace: gerbera }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gerbera } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gerbera, namespace: gerbera }
spec:
  serviceAccountName: gerbera-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gerbera/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gerbera, importPath: github.com/metio/kurly/workloads/gerbera }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gerbera, namespace: gerbera }
spec:
  serviceAccountName: gerbera-deployer
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
        name: gerbera
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gerbera }
```

<!-- END generated: jaas-deploy -->
