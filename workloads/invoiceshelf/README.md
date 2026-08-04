<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# invoiceshelf

[InvoiceShelf](https://github.com/InvoiceShelf/InvoiceShelf) — self-hosted
invoicing and estimates for freelancers and small businesses, the maintained
continuation of Crater. A plain composable `kurly.http` workload: with the default
SQLite backend its database, uploads and PDF templates all live on a
PersistentVolume, so it needs nothing external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local invoiceshelf = import 'github.com/metio/kurly/workloads/invoiceshelf/server.libsonnet';

kurly.list(invoiceshelf(appUrl='https://invoices.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `invoiceshelf` | |
| `image` | `invoiceshelf/invoiceshelf:2.4.2` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/www/html/storage` |
| `appUrl` | unset | the public URL links and PDFs are built against |
| `secretName` | `invoiceshelf` | supplies `APP_KEY` |
| `env` | `{}` | extra settings, including `DB_*` for an external database |
| `resources` / `labels` / `annotations` | | |

Serves the web app on `:8080` — compose an exposure onto it:

```jsonnet
kurly.list([
  invoiceshelf(appUrl='https://invoices.example.com')
  + kurly.expose.ownGateway('invoices.example.com', 'istio', tls='invoiceshelf-tls'),
  kurly.certificate('invoiceshelf-tls', ['invoices.example.com'], 'letsencrypt-prod'),
])
```

The first visit runs the installation wizard, which creates the administrator
account and the company profile.

## The Secret

`APP_KEY` encrypts session and database values. Left unset the entrypoint writes a
fresh one into its own `.env` — and that file is **not** on the volume, so a
restart would mint a new key and orphan everything the old one encrypted. Supply
it instead, and keep it: rotating it has the same effect.

Laravel wants 32 characters for AES-256-CBC, which is what a 32-character hex
string gives:

```shell
kubectl create secret generic invoiceshelf \
  --from-literal=APP_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Why there is an init container

`storage/` ships **content**, not only empty directories — the PDF templates the
invoice renderer loads live in `storage/app/templates/pdf`. A PersistentVolume
arrives empty and hides them, and Laravel then fails to boot:

```text
The "/var/www/html/storage/app/templates/pdf" directory does not exist.
```

Upstream's `docker compose` never meets this, because a Docker **named volume** is
seeded from the image the first time it is used. Kubernetes does no such thing.
So an init container mounts the same volume at a second path — where the image's
own `storage/` is still visible — and copies it in, guarded by a marker so it only
happens on the first boot.

It copies with `tar`, not `cp`, and that detail is load-bearing: this image's shell
is BusyBox, whose `cp -R src/. dst/` copies **nothing and exits 0**. The obvious
spelling seeds an empty volume, reports success, and the failure surfaces minutes
later as a missing directory with nothing pointing back at the cause.

## Database

`DB_CONNECTION` and `DB_DATABASE` are set explicitly rather than left to the
defaults, because the entrypoint and the framework otherwise disagree: the
entrypoint creates the SQLite file under `storage/app` when `DB_DATABASE` is
blank, while Laravel — reading the shipped `.env`, where it is blank — looks for it
under `database/`. The result is a container that waits thirty seconds for a
database that exists somewhere else, then exits.

Point the `DB_*` settings at PostgreSQL or MySQL through `env` to move off SQLite.
The uploads and templates stay on the volume either way.

## Running unprivileged

The image already selects `www-data` (uid 82) rather than starting as root, which
is unusual for a PHP application and worth having: kurly's other PHP workloads
([bookstack](../bookstack/), [snipe-it](../snipe-it/)) have to give up non-root
because their images start as it. This one keeps it.

It does relax the read-only root filesystem, because Laravel writes inside its own
install tree in places no volume belongs: `bootstrap/cache` holds the compiled
configuration, and the entrypoint creates `.env` beside the code on first boot.
Neither is worth persisting; both need the filesystem to accept a write.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the file.

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
metadata: { name: kurly, namespace: invoiceshelf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-invoiceshelf, namespace: invoiceshelf }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/invoiceshelf, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: invoiceshelf }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-invoiceshelf, namespace: invoiceshelf }
spec: { sourceRef: { kind: OCIRepository, name: kurly-invoiceshelf } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: invoiceshelf, namespace: invoiceshelf }
spec:
  serviceAccountName: invoiceshelf-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/invoiceshelf/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-invoiceshelf, importPath: github.com/metio/kurly/workloads/invoiceshelf }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: invoiceshelf, namespace: invoiceshelf }
spec:
  serviceAccountName: invoiceshelf-deployer
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
        name: invoiceshelf
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: invoiceshelf }
```

<!-- END generated: jaas-deploy -->
