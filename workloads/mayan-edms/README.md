<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mayan-edms

[Mayan EDMS](https://www.mayan-edms.com) — a document management system: it
ingests scans and files, generates previews, OCRs them, and files them away under
cabinets, tags and metadata indexes that are rebuilt as documents arrive. A
composable `kurly.http` workload running the official all-in-one image —
gunicorn and the five Celery worker classes under one `supervisord` — backed by
an external PostgreSQL and Redis, with the document store on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mayan = import 'github.com/metio/kurly/workloads/mayan-edms/server.libsonnet';

kurly.list(mayan())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mayan-edms` | |
| `image` | `docker.io/mayanedms/mayanedms:v4.11.5` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/var/lib/mayan` — every document |
| `dbHost` / `dbPort` / `database` / `dbUser` | `mayan-edms-db-rw` … | pairs with a `cnpg-cluster` named `mayan-edms-db` |
| `secretName` | `mayan-edms` | the database password and the two Celery URLs |
| `workers` | `3` | gunicorn workers in the pod |
| `env` | `{}` | extra environment (`MAYAN_WORKER_*_CONCURRENCY`, `MAYAN_LOCK_MANAGER_BACKEND`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the UI and API on `:8000` — compose an exposure onto it:

```jsonnet
kurly.list([
  mayan()
  + kurly.expose.ownGateway('documents.example.com', 'istio', tls='mayan-tls'),
  kurly.certificate('mayan-tls', ['documents.example.com'], 'letsencrypt-prod'),
])
```

## Database and broker

Mayan stores its metadata in PostgreSQL and runs everything slow — OCR, preview
generation, index rebuilds, exports — through Celery, so a Redis broker is not
optional. Pair it with the `cnpg-cluster` and `valkey` workloads.

## Supply the Secret

| key | what it is |
|---|---|
| `MAYAN_DATABASE_PASSWORD` | the PostgreSQL login |
| `MAYAN_CELERY_BROKER_URL` | `redis://:…@mayan-edms-cache:6379/0` |
| `MAYAN_CELERY_RESULT_BACKEND` | the same instance, for task results |

```shell
kubectl create secret generic mayan-edms \
  --from-literal=MAYAN_DATABASE_PASSWORD=… \
  --from-literal=MAYAN_CELERY_BROKER_URL='redis://:…@mayan-edms-cache:6379/0' \
  --from-literal=MAYAN_CELERY_RESULT_BACKEND='redis://:…@mayan-edms-cache:6379/0'
```

Django takes its whole database configuration as one setting, `MAYAN_DATABASES`,
a dict carrying the password inline. Writing that dict here would put the
password in the rendered manifest, so the connection is assembled inside the
container instead: the non-secret coordinates are plain environment, and the
image's own `MAYAN_DOCKER_SCRIPT_PRE_SETUP` hook joins them with
`MAYAN_DATABASE_PASSWORD` before anything starts. Setting `MAYAN_DATABASES`
yourself through `env` replaces that.

Mayan generates and keeps its `SECRET_KEY` at `/var/lib/mayan/system/SECRET_KEY`
on first boot, so it lives on the volume and is not a key you supply — losing
that volume invalidates every session and every encrypted field with it.

## Less hardened, deliberately

The entrypoint chowns the document store and starts every process through
`runuser`, both of which it can only do as root, so root, privilege escalation
and capabilities are relaxed. The root filesystem is writable because
`supervisord`, gunicorn and the font cache the entrypoint builds all write inside
the image's own tree.

## First boot is slow

The first start applies the whole Django migration set, builds the font cache and
installs the initial document types before gunicorn binds anything — minutes on a
small node. That is what the startup probe is for; a longer liveness delay would
not have covered it. The probes check the socket rather than a path, because `/`
redirects to the login page.

## Persistence

Documents, their previews, the caches and the generated `SECRET_KEY` share one
ReadWriteOnce volume, so this is one replica, recreated rather than rolled — a
rolling update would leave two pods contending for a volume that attaches to one
node.

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
metadata: { name: kurly, namespace: mayan-edms }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mayan-edms, namespace: mayan-edms }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mayan-edms, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mayan-edms }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mayan-edms, namespace: mayan-edms }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mayan-edms } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mayan-edms, namespace: mayan-edms }
spec:
  serviceAccountName: mayan-edms-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mayan-edms/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mayan-edms, importPath: github.com/metio/kurly/workloads/mayan-edms }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mayan-edms, namespace: mayan-edms }
spec:
  serviceAccountName: mayan-edms-deployer
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
        name: mayan-edms
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mayan-edms }
```

<!-- END generated: jaas-deploy -->
