<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pdfding

[PdfDing](https://github.com/mrmn2/PdfDing) — a PDF manager, viewer and editor:
upload documents, tag and search them, and pick up reading where you left off. A
plain composable `kurly.http` workload; the uploaded PDFs and the SQLite database
live together under `DATA_DIR` on a PersistentVolume, so it needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pdfding = import 'github.com/metio/kurly/workloads/pdfding/server.libsonnet';

kurly.list(pdfding(hostName='pdf.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pdfding` | |
| `image` | `mrmn/pdfding:v1.12.0` | |
| `hostName` | `pdfding.example.com` | Django `ALLOWED_HOSTS`; comma-separate several |
| `dataDir` | `/data` | media tree + SQLite database |
| `storageSize` / `storageClass` | `10Gi` / cluster default | mounted at `dataDir` |
| `secretName` | `pdfding` | holds `SECRET_KEY` |
| `env` / `resources` / `labels` / `annotations` | | |

## Set `hostName`, or nothing works

`HOST_NAME` becomes Django's `ALLOWED_HOSTS`. A request whose `Host` header is not
in that list is answered `400` before any view runs, so the placeholder default
holds only until the instance is really reachable somewhere. Set it to the name
the exposure serves.

That is also why the probes check the **listening socket** rather than an HTTP
path: a probe arriving with the pod IP as its `Host` would fail forever against a
perfectly healthy pod and restart it in a loop.

## The Secret

`SECRET_KEY` signs sessions and password-reset links. Rotating it logs everybody
out; sharing it between instances lets each sign the other's cookies. Put a large
random value in the Secret named by `secretName` — it is read with `envFrom`, so
`POSTGRES_PASSWORD` and anything else the app takes from the environment can ride
along in the same object.

Cookies are marked `Secure` by default (`CSRF_COOKIE_SECURE`,
`SESSION_COOKIE_SECURE`), which is right behind TLS and breaks sign-in over plain
HTTP — set both to `FALSE` through `env` only if you really are serving without it.

## Persistence

One SQLite database and one media tree on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled). Point `DATABASE_TYPE=POSTGRES` and the
`POSTGRES_*` variables at an external server through `env` to move the database
off the volume; the uploaded PDFs stay on it either way.

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
metadata: { name: kurly, namespace: pdfding }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pdfding, namespace: pdfding }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pdfding, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pdfding }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pdfding, namespace: pdfding }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pdfding } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pdfding, namespace: pdfding }
spec:
  serviceAccountName: pdfding-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pdfding/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pdfding, importPath: github.com/metio/kurly/workloads/pdfding }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pdfding, namespace: pdfding }
spec:
  serviceAccountName: pdfding-deployer
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
        name: pdfding
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pdfding }
```

<!-- END generated: jaas-deploy -->
