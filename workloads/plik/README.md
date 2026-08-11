<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# plik

[Plik](https://plik.root.gg) — a temporary file upload and sharing server, with a
web app, a REST API and a command-line client. A plain composable `kurly.http`
workload: uploads land on a PersistentVolume and their metadata in a SQLite
database beside them, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local plik = import 'github.com/metio/kurly/workloads/plik/server.libsonnet';

kurly.list(plik(plikDomain='https://plik.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `plik` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploads and the SQLite database (`/data`) |
| `plikDomain` | none | the public URL download links are built against |
| `config` | `{}` | merged over the rendered `plikd.cfg` |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8080` — compose an exposure onto it.

## Configuration

`plikd.cfg` is rendered as a ConfigMap and mounted over the image's own copy. The
paths it names are absolute, because Plik resolves its defaults (`files`,
`plik.db`) relative to a working directory inside the read-only image — both have
to be moved onto the volume for the server to start at all. Everything else Plik
can be told is reachable through `config`, which merges over those defaults.

Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
recreated (never rolled) to keep two pods off the file.

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
metadata: { name: kurly, namespace: plik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-plik, namespace: plik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/plik, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: plik }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-plik, namespace: plik }
spec: { sourceRef: { kind: OCIRepository, name: kurly-plik } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: plik, namespace: plik }
spec:
  serviceAccountName: plik-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/plik/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-plik, importPath: github.com/metio/kurly/workloads/plik }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: plik, namespace: plik }
spec:
  serviceAccountName: plik-deployer
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
        name: plik
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: plik }
```

<!-- END generated: jaas-deploy -->
