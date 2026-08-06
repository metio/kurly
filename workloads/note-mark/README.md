<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# note-mark

[Note Mark](https://github.com/enchant97/note-mark) — a small web-based Markdown
notes app. One Go binary serves both the API and the compiled frontend. A plain
composable `kurly.http` workload: notes, uploaded assets and the SQLite database
live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local notemark = import 'github.com/metio/kurly/workloads/note-mark/server.libsonnet';

kurly.list(
  notemark(publicUrl='https://notes.example.com')
  + kurly.expose.gateway('notes.example.com', 'gateway', 'infra')
)
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `note-mark` | |
| `image` | `ghcr.io/enchant97/note-mark:1.0.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | notes, assets and `db.sqlite` (`/data`) |
| `publicUrl` | `http://localhost:8080` | the URL a browser reaches this instance at |
| `secretName` | `note-mark` | Secret with `AUTH_TOKEN__SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the app and its API on `:8080` — compose an exposure onto it.

## The public URL

`PUBLIC_URL` is deployment-specific and the app refuses to start without a valid
one, so the default is a localhost URL that boots and is wrong everywhere it is
really deployed. Set it to the host the browser reaches, **without a trailing
slash** — the app validates that too.

## Secrets

`AUTH_TOKEN__SECRET` signs the session tokens and must be base64 of at least 32
bytes. kurly authors **no Secret** — provide `note-mark` holding that key, pulled
in via `envFrom`.

## Persistence

The SQLite database and the asset tree live on a ReadWriteOnce volume, so this is
**one replica, recreated**.

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
metadata: { name: kurly, namespace: note-mark }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-note-mark, namespace: note-mark }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/note-mark, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: note-mark }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-note-mark, namespace: note-mark }
spec: { sourceRef: { kind: OCIRepository, name: kurly-note-mark } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: note-mark, namespace: note-mark }
spec:
  serviceAccountName: note-mark-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/note-mark/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-note-mark, importPath: github.com/metio/kurly/workloads/note-mark }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: note-mark, namespace: note-mark }
spec:
  serviceAccountName: note-mark-deployer
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
        name: note-mark
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: note-mark }
```

<!-- END generated: jaas-deploy -->
