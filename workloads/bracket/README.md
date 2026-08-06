<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bracket

[Bracket](https://github.com/evroon/bracket) — a tournament system: clubs, teams,
players and courts, and the single-elimination, round-robin and swiss stages that
decide them. A composable `kurly.http` workload backed by an external PostgreSQL,
with uploaded club and team logos on a PersistentVolume.

**This is the backend image.** It answers the API and serves the uploaded logos
under `/static`. The web frontend is a separate image and is not carried here, so
what this workload exposes is an API, not a web application.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bracket = import 'github.com/metio/kurly/workloads/bracket/server.libsonnet';

kurly.list(bracket())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bracket` | |
| `image` | `ghcr.io/evroon/bracket-backend:v2.2.5` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/app/static` |
| `baseUrl` | unset | the public URL the API is reached at |
| `corsOrigins` | unset | the frontend's origin; the application's own default is `*` |
| `adminEmail` | `admin@example.com` | the administrator created on first start |
| `secretName` | `bracket` | see below |

## Supply the Secret

| key | what it is |
|---|---|
| `PG_DSN` | the whole `postgresql://user:pass@host:5432/db` connection string |
| `JWT_SECRET` | signs the tokens users hold; required, the application will not start without it |
| `ADMIN_PASSWORD` | the password of the administrator created on the first start |

```shell
kubectl create secret generic bracket \
  --from-literal=PG_DSN=postgresql://bracket:…@bracket-db-rw:5432/bracket \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=ADMIN_PASSWORD=…
```

Point `PG_DSN` at a PostgreSQL that is backed up — a `cnpg-cluster` named
`bracket-db` gives you one. Alembic migrates the schema on the first start, which
is why the first boot is slow and guarded by a startup probe.

## `ADMIN_PASSWORD` reads optional and is not

Bracket populates an empty database only from the branch that also creates the
administrator account. With no `ADMIN_EMAIL` / `ADMIN_PASSWORD` the tables are
never created, the Alembic run that follows tries to drop an index no table has,
and the process exits — a fresh install simply never starts. So set `adminEmail`
and put an `ADMIN_PASSWORD` in the Secret.

User registration is open by default; set `ALLOW_USER_REGISTRATION=false` through
`env` once your accounts exist.

## Persistence

Uploaded tournament and team logos live on a ReadWriteOnce volume, so this is
**one replica, recreated** (never rolled). Everything else is in PostgreSQL.

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
metadata: { name: kurly, namespace: bracket }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bracket, namespace: bracket }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bracket, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bracket }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bracket, namespace: bracket }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bracket } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bracket, namespace: bracket }
spec:
  serviceAccountName: bracket-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bracket/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bracket, importPath: github.com/metio/kurly/workloads/bracket }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bracket, namespace: bracket }
spec:
  serviceAccountName: bracket-deployer
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
        name: bracket
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bracket }
```

<!-- END generated: jaas-deploy -->
