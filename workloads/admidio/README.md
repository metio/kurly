<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# admidio

[Admidio](https://www.admidio.org/) — member management for clubs and
organisations: the people, the roles they hold, the events they attend and the
mailings that go out to them. A plain composable `kurly.http` workload on the
project's own image, backed by an external MySQL/MariaDB or PostgreSQL, with its
generated configuration and uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local admidio = import 'github.com/metio/kurly/workloads/admidio/server.libsonnet';

kurly.list(admidio(rootPath='https://members.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `admidio` | |
| `image` | `docker.io/admidio/admidio:v5.0.14` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `adm_my_files` — config and uploads |
| `dbType` | `mysql` | `mysql` (also MariaDB) or `pgsql` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `admidio-db` / `3306` / `admidio` / `admidio` | |
| `rootPath` | unset | the public URL Admidio builds links against |
| `organisation` | unset | short name of the organisation being installed |
| `mailRelayHost` | unset | the SMTP relay postfix hands mail to |
| `secretName` | `admidio` | Secret with `ADMIDIO_DB_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:8080` — compose an exposure onto it.

## Database and secrets

Admidio needs a **MySQL/MariaDB** or **PostgreSQL** database — the
[mysql-cluster](../mysql-cluster/) and [cnpg-cluster](../cnpg-cluster/) workloads
provide one. `dbType` decides which dialect the generated `config.php` speaks, and
must match the server it points at. The coordinates travel as environment, while
`ADMIDIO_DB_PASSWORD` comes from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `admidio` with
[`kurly.externalSecret`](../../main.libsonnet).

Set `rootPath` to the URL the installation is reached at. Left unset, Admidio keeps
the placeholder from its shipped example configuration and every generated link —
including the ones in password-reset mail — points somewhere that is not this
installation.

Mail is handed to a local postfix, which delivers nothing until `mailRelayHost`
names a relay it may hand messages to.

## Security and persistence

The entrypoint provisions the application tree into the document root, chowns it to
`www-data`, rewrites the Apache port configuration and starts cron and postfix
before Apache forks its workers as `www-data`. All of that needs **root**, its
capabilities and a **writable image tree**, so this workload relaxes those defaults
deliberately. Configuration and uploads live on a ReadWriteOnce volume, so this is
**one replica, recreated**.

The first request lands on the installation wizard, which walks an administrator
through creating the schema and the first organisation. The probes are therefore by
**connection**, not by path: the document root redirects until that walk is done.

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
metadata: { name: kurly, namespace: admidio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-admidio, namespace: admidio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/admidio, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: admidio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-admidio, namespace: admidio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-admidio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: admidio, namespace: admidio }
spec:
  serviceAccountName: admidio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/admidio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-admidio, importPath: github.com/metio/kurly/workloads/admidio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: admidio, namespace: admidio }
spec:
  serviceAccountName: admidio-deployer
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
        name: admidio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: admidio }
```

<!-- END generated: jaas-deploy -->
