<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# karaoke-eternal

[Karaoke Eternal](https://github.com/bhj/KaraokeEternal) — hosts a karaoke party:
the room screen plays the songs, and guests queue them from their own phone
browser. A plain composable `kurly.http` workload; the SQLite database and the
media library live on PersistentVolumes, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local karaokeEternal = import 'github.com/metio/kurly/workloads/karaoke-eternal/server.libsonnet';

kurly.list(karaokeEternal())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `karaoke-eternal` | |
| `image` | `radrootllc/karaoke-eternal:2.0.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/config`, the SQLite database |
| `mediaSize` / `mediaStorageClass` / `mediaAccessModes` | `50Gi` / cluster default / `ReadWriteOnce` | `/mnt/karaoke`, the song library |
| `env` / `resources` / `labels` / `annotations` | | `KES_SCAN=1` runs the media scanner at startup |

Serves on `:8080` — the port the image's own command line binds — so compose an
exposure onto it.

## Create the administrator before you publish the URL

The **first account registered becomes the administrator**. On an instance
reachable from the internet that is whoever arrives first. Register yours as soon
as the pod is ready, before handing the address to anyone.

## The library is a second volume

`/config` holds the database and the server's own state; `/mnt/karaoke` holds the
songs, and is the path to name when adding a media folder in the app. They are
separate claims because a library outgrows a database by two orders of magnitude,
and on shared storage the library is often a `ReadWriteMany` claim filled by
something else entirely — `mediaAccessModes` is there for that.

Add media by writing into that volume, then run the scanner from the app (or set
`KES_SCAN=1` so it runs at startup). Filenames are read as `Artist - Title`
unless a `_kes.v2.json` in the folder says otherwise.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled): two pods writing the same database file is not
something SQLite will sort out afterwards.

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
metadata: { name: kurly, namespace: karaoke-eternal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-karaoke-eternal, namespace: karaoke-eternal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/karaoke-eternal, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: karaoke-eternal }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-karaoke-eternal, namespace: karaoke-eternal }
spec: { sourceRef: { kind: OCIRepository, name: kurly-karaoke-eternal } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: karaoke-eternal, namespace: karaoke-eternal }
spec:
  serviceAccountName: karaoke-eternal-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/karaoke-eternal/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-karaoke-eternal, importPath: github.com/metio/kurly/workloads/karaoke-eternal }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: karaoke-eternal, namespace: karaoke-eternal }
spec:
  serviceAccountName: karaoke-eternal-deployer
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
        name: karaoke-eternal
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: karaoke-eternal }
```

<!-- END generated: jaas-deploy -->
