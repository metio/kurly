<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redash

[Redash](https://github.com/getredash/redash) — connect a data source, write a
query, save it, and put the result on a dashboard other people read. Three
composable stages on the official image: `server` (the web UI and API,
`kurly.http`), `worker` (the RQ worker that actually runs the queries) and
`scheduler` (the RQ scheduler that enqueues the periodic ones). State lives in an
external PostgreSQL and an external Redis, so no stage claims a volume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redash = import 'github.com/metio/kurly/workloads/redash/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/redash/worker.libsonnet';
local scheduler = import 'github.com/metio/kurly/workloads/redash/scheduler.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/cache.libsonnet';

kurly.list([
  cnpg(name='redash-db', database='redash'),
  valkey(name='redash-cache'),
  redash(host='https://redash.example.com'),
  worker(),
  scheduler(),
])
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `redash` | |
| `image` | the pinned default | |
| `host` | `http://localhost:5000` | the public URL links and mails are built from |
| `secretName` | `redash` | Secret with `REDASH_DATABASE_URL`, `REDASH_REDIS_URL`, `REDASH_SECRET_KEY`, `REDASH_COOKIE_SECRET` (envFrom) |
| `webWorkers` | `4` | gunicorn worker processes in the pod |
| `passwordLoginEnabled` / `inviteOnly` | `true` / `true` | who may sign in, and who may create an account |
| `replicas` | `1` | |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the UI and API on `:5000` — compose an exposure onto it.

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `redash-worker` | |
| `secretName` | `redash` | the same Secret the server reads |
| `queues` | `queries,scheduled_queries,schemas,default,periodic` | which RQ queues this deployment drains |
| `workersCount` | `2` | worker processes in one pod |
| `replicas` | `1` | scales horizontally |
| `env` / `resources` / `labels` / `annotations` | | |

### `scheduler`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `redash-scheduler` | |
| `secretName` | `redash` | the same Secret the server reads |
| `env` / `resources` / `labels` / `annotations` | | |

## Run all three

The web server only *enqueues* work. Without a `worker` a query submitted from the
UI waits forever, and without the `scheduler` no query ever refreshes on its own.
Run all three against the same database, Redis and Secret.

The scheduler is **one replica and takes no `replicas` parameter**: a second
instance enqueues the same periodic jobs, doubling the load on the data sources
while changing nothing a user sees. Workers scale freely — they coordinate through
the shared Redis queues, and a second worker stage with `queues='queries'` keeps ad
hoc queries off the pods running the scheduled ones.

## Database and cache

The defaults pair with a [cnpg-cluster](../cnpg-cluster/) and a
[valkey](../valkey/). Both connection strings carry credentials, so they live in
the Secret rather than in `env`.

**The schema is not migrated on start.** The image carries the migration as its
own entrypoint command — `create_db` against an empty database, `manage db
upgrade` after an upgrade — so a fresh deployment runs it once before these stages
are useful:

```shell
kubectl run redash-create-db --rm -it --restart=Never \
  --image=redash/redash:26.3.0 --env=REDASH_DATABASE_URL=… -- create_db
```

## Secrets

`REDASH_DATABASE_URL`, `REDASH_REDIS_URL`, `REDASH_SECRET_KEY` and
`REDASH_COOKIE_SECRET` are read from the environment via `envFrom`. kurly authors
**no Secret**.

`REDASH_COOKIE_SECRET` signs the session cookie — a value that changes on every
restart signs everybody out. `REDASH_SECRET_KEY` encrypts the **data source
credentials** stored in the database, so changing it later leaves every configured
data source unreadable rather than merely re-authenticating.

## Probes

Probed by connection. The root path redirects an unauthenticated visitor to the
login form, and a probe that follows a redirect fails the day the redirect changes.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: redash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-redash, namespace: redash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/redash, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: redash }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-redash, namespace: redash }
spec: { sourceRef: { kind: OCIRepository, name: kurly-redash } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redash-scheduler, namespace: redash }
spec:
  serviceAccountName: redash-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local scheduler = import 'github.com/metio/kurly/workloads/redash/scheduler.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(scheduler())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redash, importPath: github.com/metio/kurly/workloads/redash }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redash-server, namespace: redash }
spec:
  serviceAccountName: redash-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/redash/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redash, importPath: github.com/metio/kurly/workloads/redash }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redash-worker, namespace: redash }
spec:
  serviceAccountName: redash-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/redash/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redash, importPath: github.com/metio/kurly/workloads/redash }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: redash, namespace: redash }
spec:
  serviceAccountName: redash-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: scheduler
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redash-scheduler
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redash-scheduler }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redash-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redash-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: redash-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redash-worker }
```

<!-- END generated: jaas-deploy -->
