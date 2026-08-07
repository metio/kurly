<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# myfin-budget

[MyFin](https://github.com/afaneca/myfin) — a personal finance platform for
budgeting, tracking income and spending, and forecasting what the months ahead
look like. This workload carries the **API server**, a composable `kurly.http`
workload backed by an external MySQL/MariaDB and claiming no volume of its own.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local myfin = import 'github.com/metio/kurly/workloads/myfin-budget/server.libsonnet';

kurly.list(myfin())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `myfin-budget` | |
| `image` | `ghcr.io/afaneca/myfin-api:5.0.4` | |
| `replicas` | `1` | stateless, so more is fine |
| `secretName` | `myfin-budget` | database and SMTP, see below |
| `env` | `{}` | anything else the server reads |

## The browser client is separate software

MyFin is two published pieces: this API and a static web bundle that talks to it.
Nothing here serves the bundle — put it wherever static files belong for you and
point it at the exposure composed onto this Service. The API answers `GET /` with
its own name and version, which is what the probes use.

## Supply the Secret

The connection string is read from `DATABASE_URL` first. If that is absent, the
server assembles one from `DB_NAME`, `DB_USER`, `DB_PW`, `DB_HOST` and `DB_PORT`
— either form works, and both belong in the Secret rather than in `env`.

```shell
kubectl create secret generic myfin-budget \
  --from-literal=DATABASE_URL='mysql://myfin:…@myfin-db:3306/myfin'
```

The one-time codes MyFin mails during login and password reset need an SMTP
server, so `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASSWORD`
and `SMTP_FROM` go into the same Secret. Without them the account exists and the
mail that unlocks it never arrives.

Two settings worth deciding before anyone can reach the exposure:
`ENABLE_USER_SIGNUP` defaults to `true`, which lets anybody who finds the API
create an account, and `TRUST_PROXY` decides how many hops of `X-Forwarded-For`
the rate limiter believes — it defaults to `1`, which is right behind exactly one
proxy and wrong behind two.

## The first start migrates

`prisma migrate deploy` applies the migration ladder against the database and only
then does the server listen, so this has a startup probe rather than a generous
liveness delay. The migration runner takes an advisory lock in MySQL, so several
replicas starting at once is safe: one applies the ladder and the rest wait.

The hardened default holds — non-root as the image's own `1000:1000`, no
capabilities, read-only root filesystem — with a scratch at `/tmp`, which is
where npm and the Prisma CLI write while the migration runs.

## Persistence

There is none here. Accounts, transactions, budgets and sessions are all in
MySQL, so `storage.pvcs` is 0 and backing up the database backs up the
installation. Point it at one that is backed up.

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
metadata: { name: kurly, namespace: myfin-budget }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-myfin-budget, namespace: myfin-budget }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/myfin-budget, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: myfin-budget }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-myfin-budget, namespace: myfin-budget }
spec: { sourceRef: { kind: OCIRepository, name: kurly-myfin-budget } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: myfin-budget, namespace: myfin-budget }
spec:
  serviceAccountName: myfin-budget-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/myfin-budget/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-myfin-budget, importPath: github.com/metio/kurly/workloads/myfin-budget }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: myfin-budget, namespace: myfin-budget }
spec:
  serviceAccountName: myfin-budget-deployer
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
        name: myfin-budget
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: myfin-budget }
```

<!-- END generated: jaas-deploy -->
