<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# discount-bandit

[Discount Bandit](https://discount-bandit.cybrarist.com/) — tracks the price and stock
of products across Amazon, eBay, AliExpress and custom stores, and notifies you when a
price meets the criteria you set. A plain composable `kurly.http` workload on the
official image, backed by an external MySQL/MariaDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bandit = import 'github.com/metio/kurly/workloads/discount-bandit/server.libsonnet';

kurly.list(bandit(appUrl='https://prices.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `discount-bandit` | |
| `image` | the pinned official image | |
| `dbHost` / `dbPort` / `dbName` / `dbUser` | `discount-bandit-db` / `3306` / `discount-bandit` / `discount-bandit` | the MySQL/MariaDB database |
| `appUrl` | unset | the public URL, used for links and assets |
| `cron` | `*/5 * * * *` | how often the scheduler re-checks every tracked product |
| `timezone` | `UTC` | |
| `secretName` | `discount-bandit` | Secret with `APP_KEY` and `DB_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

The image ships SQLite as Laravel's default and creates no database file, so this
stage runs it on **MySQL/MariaDB** instead — the [mysql-cluster](../mysql-cluster/)
workload provides one. Database coordinates come from env; `DB_PASSWORD` and `APP_KEY`
come from a provided Secret via `envFrom`. `APP_KEY` is Laravel's encryption key — a
32-character string, and everything encrypted under the previous one is unreadable
once it changes. kurly authors **no Secret**.

## What the pod does

`FRANKEN_HOST` is set to `0.0.0.0`. The image bakes `localhost`, which Octane passes to
FrankenPHP as its listen address, so the default binds the loopback interface only and
every request through the Service is refused by a pod that looks healthy.

Everything else happens in the container's own tree: the entrypoint copies `.env` into
`/app`, links storage, runs the migrations and writes Laravel's compiled caches back
beside the code, then supervisord runs Octane, the scheduler and the queue worker as
root. Hence root and a writable root filesystem, with all capabilities dropped and no
privilege escalation. Scraped pages are rendered by a headless Chromium in the same
pod.

The first start migrates and seeds the database, warms the Filament and Laravel caches
and installs Octane before anything listens, so the stage carries a startup probe
rather than a stretched liveness delay. Probes are connection checks: Octane validates
the Host header on the routes it answers.

The pod runs the cron scheduler and the queue worker alongside the web server, so a
second replica would scrape every tracked product twice — one replica, recreated.

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
metadata: { name: kurly, namespace: discount-bandit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-discount-bandit, namespace: discount-bandit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/discount-bandit, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: discount-bandit }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-discount-bandit, namespace: discount-bandit }
spec: { sourceRef: { kind: OCIRepository, name: kurly-discount-bandit } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: discount-bandit, namespace: discount-bandit }
spec:
  serviceAccountName: discount-bandit-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/discount-bandit/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-discount-bandit, importPath: github.com/metio/kurly/workloads/discount-bandit }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: discount-bandit, namespace: discount-bandit }
spec:
  serviceAccountName: discount-bandit-deployer
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
        name: discount-bandit
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: discount-bandit }
```

<!-- END generated: jaas-deploy -->
