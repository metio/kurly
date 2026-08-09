<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# traduora

[ever-traduora](https://github.com/ever-co/ever-traduora) — a translation
management platform: teams edit their locales in a web UI, and an import/export
API moves the same strings in and out of a build. A composable `kurly.http`
workload backed by an external PostgreSQL, holding no state of its own.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local traduora = import 'github.com/metio/kurly/workloads/traduora/server.libsonnet';

kurly.list(traduora())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `traduora` | |
| `image` | `docker.io/everco/ever-traduora:v0.21.0` | |
| `dbType` | `postgres` | traduora's own vocabulary: `postgres` or `mysql` |
| `dbHost` / `dbPort` / `database` | `traduora-db-rw` / `5432` / `traduora` | pairs with a `cnpg-cluster` named `traduora-db` |
| `virtualHost` | `http://localhost:8080` | the URL users reach this instance on |
| `signupsEnabled` | `true` | set `false` once the accounts you want exist |
| `secretName` | `traduora` | three credentials, see below |

## Supply the Secret — the token signing key has a published default

`TR_SECRET` signs every access token traduora issues, and upstream ships it as
the literal string `secret`. Running with that is not a weakened posture — it
means anybody who has read the repository can mint a token for any account.

| key | what it is |
|---|---|
| `TR_DB_USER` | the database login |
| `TR_DB_PASSWORD` | its password |
| `TR_SECRET` | signs access tokens |

```shell
kubectl create secret generic traduora \
  --from-literal=TR_DB_USER=traduora \
  --from-literal=TR_DB_PASSWORD=… \
  --from-literal=TR_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## PostgreSQL, not MariaDB

`dbType` takes traduora's own vocabulary and PostgreSQL is the default: an early
traduora migration alters a column another table's foreign key depends on, which
MariaDB refuses, so the first boot fails there before the server ever listens.

## The database, and the first start

`TR_DB_AUTOMIGRATE` is on, so the schema is created and upgraded when the
process starts — the first boot serves nothing until that finishes, which is
why the startup probe is generous rather than the liveness probe. Point
`dbHost` at a database that is backed up: it holds every project, term and
translation.

## `virtualHost` goes into the mail

Invitation and password-reset links are built from `TR_VIRTUAL_HOST`, so leaving
it at the default produces mails pointing at `localhost`. Set it to the address
your exposure serves.

## Hardening

The image sets no `USER`, so this runs explicitly as uid/gid 1000 (`node` in
the base image) to keep the hardened default. The root filesystem stays
read-only, with a scratch volume at `/tmp` for node's temporary files.

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
metadata: { name: kurly, namespace: traduora }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-traduora, namespace: traduora }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/traduora, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: traduora }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-traduora, namespace: traduora }
spec: { sourceRef: { kind: OCIRepository, name: kurly-traduora } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: traduora, namespace: traduora }
spec:
  serviceAccountName: traduora-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/traduora/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-traduora, importPath: github.com/metio/kurly/workloads/traduora }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: traduora, namespace: traduora }
spec:
  serviceAccountName: traduora-deployer
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
        name: traduora
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: traduora }
```

<!-- END generated: jaas-deploy -->
