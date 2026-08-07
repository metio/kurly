<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bitcart

[Bitcart](https://github.com/bitcart/bitcart) — a self-hosted cryptocurrency payment
processor: stores, invoices, wallets, and the merchants API the admin panel and
storefront talk to. A composable `kurly.http` workload on the official backend image,
backed by an external PostgreSQL and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bitcart = import 'github.com/metio/kurly/workloads/bitcart/server.libsonnet';

kurly.list(bitcart(apiHost='api.example.com', adminHost='admin.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bitcart` | |
| `image` | `docker.io/bitcart/bitcart:0.10.3.0` | |
| `apiHost` / `adminHost` | `localhost:8000` / `localhost:3000` | the public hosts absolute links are built from |
| `cryptos` | `btc` | `BITCART_CRYPTOS`; each coin needs its own daemon |
| `workers` | `4` | gunicorn workers — its own default counts the node's CPUs, not the container's |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the datadir (`/datadir`) |
| `dbHost` / `dbName` / `dbUser` | `bitcart-db-rw` / `bitcart` / `bitcart` | pairs with a [cnpg-cluster](../cnpg-cluster/) named `bitcart-db` |
| `redisHost` | `bitcart-cache-headless` | pairs with a [valkey](../valkey/) named `bitcart-cache` |
| `secretName` | `bitcart` | must hold `DB_PASSWORD` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the API on `:8000` — compose an exposure onto it.

## Backends and secrets

PostgreSQL and Redis are external and their non-secret connection settings are env.
kurly authors no Secret: provide one holding `DB_PASSWORD`, which the stage pulls in
with `envFrom`.

The schema is upgraded by the container's own command, before gunicorn — the same
thing the upstream compose deployment does, since the API never migrates itself. The
first boot therefore takes minutes, which is what the startup probe is for.

The API fetches its plugin schema from `bitcart.ai` at startup and does not catch a
failure, so a cluster that blocks egress keeps it from booting.

## Security posture

The image's entrypoint runs as root — it adds a group, chowns the datadir, and only
then drops to the `electrum` account with `gosu`. That needs `rootUser`,
`allowPrivilegeEscalation` and `keepCapabilities`, plus a writable root filesystem
for the `/etc` writes `groupadd` makes; nothing beyond that is relaxed.

## Persistence

Uploaded images, plugin trees and backups default to directories inside the
application's own install tree. All of them are pointed at one PersistentVolume
instead. That volume is ReadWriteOnce, so this is **one replica, recreated** — the
same single-writer discipline as [vaultwarden](../vaultwarden/).

## What this does not carry

A full Bitcart deployment also runs a background worker and one coin daemon per
enabled cryptocurrency. This workload is the merchants API alone: it serves stores,
invoices and the admin API, but nothing here watches a chain, so payments are not
detected until you run those alongside it.

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
metadata: { name: kurly, namespace: bitcart }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bitcart, namespace: bitcart }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bitcart, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bitcart }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bitcart, namespace: bitcart }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bitcart } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bitcart, namespace: bitcart }
spec:
  serviceAccountName: bitcart-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bitcart/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bitcart, importPath: github.com/metio/kurly/workloads/bitcart }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bitcart, namespace: bitcart }
spec:
  serviceAccountName: bitcart-deployer
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
        name: bitcart
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bitcart }
```

<!-- END generated: jaas-deploy -->
