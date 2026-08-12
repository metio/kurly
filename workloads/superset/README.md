<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# superset

[Apache Superset](https://superset.apache.org/) — a business-intelligence web
application for exploring databases, building charts and assembling dashboards.
Two composable stages holding no state of their own: metadata goes to an external
PostgreSQL and the query cache and async results to Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/superset/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/superset/worker.libsonnet';

kurly.list([
  server(),
  worker(),
  worker(name='superset-beat', beat=true),
])
```

| Parameter (server) | Default | Notes |
|---|---|---|
| `name` | `superset` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | stateless, so scale freely |
| `dbHost` / `dbPort` / `dbName` / `dbUser` | `superset-db-rw` / `5432` / `superset` / `superset` | the metadata PostgreSQL |
| `redisHost` / `redisPort` | `superset-cache` / `6379` | |
| `secretName` | `superset` | `SUPERSET_SECRET_KEY` and `DB_PASS` |
| `webWorkers` | `4` | gunicorn workers, each a full Superset process |
| `extraConfig` | `''` | appended to `superset_config.py`, verbatim |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

The worker stage takes the same database and Redis parameters, plus `beat` (run
the celery scheduler instead of a worker) and `concurrency`.

Serves the web UI and API on `:8088` — compose an exposure onto it.

## The secret key encrypts every stored database password

Superset keeps the credentials of the databases it queries in its metadata
database, encrypted with `SECRET_KEY`. A key that changes makes every one of those
connections unreadable, and Superset refuses to start rather than pretend
otherwise:

```shell
kubectl create secret generic superset \
  --from-literal=SUPERSET_SECRET_KEY="$(openssl rand -base64 42)" \
  --from-literal=DB_PASS='…'
```

Rotating it is a documented Superset procedure, not an edit here. The rendered
`superset_config.py` reads `DB_PASS` from the environment rather than embedding
it, so the metadata credential never lands in a ConfigMap.

## It migrates itself before it serves

An init container runs `superset db upgrade` and `superset init` against the
metadata database. Both are idempotent, which is what lets a fresh deployment come
up without a manual step. The first run on an empty database takes minutes, which
is why the startup probe's budget is long: a shorter one restarts the pod
mid-migration and the next attempt starts over.

## Without a worker, features fail silently

A Superset with no worker still serves dashboards, and asynchronous queries queue
forever, alerts never fire and reports never arrive — with nothing in the web
server's log saying so. Deploy one, or turn those features off. Anything
time-based additionally needs the celery beat scheduler (`beat=true`), and exactly
one may run: two schedulers double-fire every scheduled task.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: superset }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-superset, namespace: superset }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/superset, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: superset }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-superset, namespace: superset }
spec: { sourceRef: { kind: OCIRepository, name: kurly-superset } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: superset-server, namespace: superset }
spec:
  serviceAccountName: superset-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/superset/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-superset, importPath: github.com/metio/kurly/workloads/superset }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: superset-worker, namespace: superset }
spec:
  serviceAccountName: superset-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/superset/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-superset, importPath: github.com/metio/kurly/workloads/superset }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: superset, namespace: superset }
spec:
  serviceAccountName: superset-deployer
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
        name: superset-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: superset-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: superset-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: superset-worker }
```

<!-- END generated: jaas-deploy -->
