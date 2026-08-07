<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# plumio

[Plumio](https://github.com/albertasaftei/plumio) — Markdown notes with a live
preview, optional end-to-end encryption, and organisations several people share. A
plain composable `kurly.http` workload that keeps its SQLite database and the note
files themselves on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local plumio = import 'github.com/metio/kurly/workloads/plumio/server.libsonnet';

kurly.list(plumio(appUrl='https://notes.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `plumio` | |
| `image` | `ghcr.io/albertasaftei/plumio:2.10.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the data volume (`/data`) |
| `secretName` | `plumio` | holds `JWT_SECRET` and `ENCRYPTION_KEY` |
| `appUrl` | absent | the URL users reach this instance at |
| `env` | `{}` | extra settings, e.g. the `SMTP_*` block |
| `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Ports

The image runs two Node processes: the API on `:3001` and the web front end on
`:3000`. The front end proxies `/api/*` to the API itself, so publishing `:3000` is
enough for a browser and the API port stays off the Service — a second route to the
same data, with none of the front end's own handling, is not worth opening.

## The Secret

`secretName` must exist before the pod starts; the image ships neither key.

- `JWT_SECRET` signs the tokens users hold. Replacing it logs everybody out.
- `ENCRYPTION_KEY` is what makes an encrypted note readable again. **Losing it
  loses the notes it protected** — there is no reset that recovers one without it,
  which is the point of the feature. Back it up somewhere other than the cluster.

## The public URL

`appUrl` reaches the app as `APP_URL` (the links it puts in mail) and as
`ALLOWED_ORIGINS` (the browser origins the API answers). It has no default on
purpose: a value chosen here would be wrong everywhere the workload is really
deployed. Mail also needs the `SMTP_*` settings through `env`.

## Persistence

One SQLite database and the note files on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[memos](../memos/).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: plumio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-plumio, namespace: plumio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/plumio, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: plumio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-plumio, namespace: plumio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-plumio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: plumio, namespace: plumio }
spec:
  serviceAccountName: plumio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/plumio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-plumio, importPath: github.com/metio/kurly/workloads/plumio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: plumio, namespace: plumio }
spec:
  serviceAccountName: plumio-deployer
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
        name: plumio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: plumio }
```

<!-- END generated: jaas-deploy -->
