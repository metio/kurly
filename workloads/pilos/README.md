<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pilos

[PILOS](https://github.com/THM-Health/PILOS) — an open-source, Laravel-based front-end
for [BigBlueButton](https://bigbluebutton.org/), developed at TH Mittelhessen: room and
meeting management with LDAP/OIDC support. A plain composable `kurly.http` workload on
the official all-in-one image (nginx + php-fpm), backed by an external PostgreSQL and
Redis, with its uploaded assets on a PersistentVolume. It reaches an existing
BigBlueButton server over the network — kurly does not run BBB itself.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pilos = import 'github.com/metio/kurly/workloads/pilos/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='pilos-db', database='pilos'),
  pilos(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pilos` | |
| `image` | `docker.io/pilos/pilos:4.17.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploaded assets (`/var/www/html/storage/app`) |
| `secretName` | `pilos-secrets` | database/Redis/`APP_KEY`/BBB settings (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Backends and secrets

PILOS reads its database, Redis, `APP_KEY` and the BigBlueButton server list from the
environment. kurly authors **no Secret** — provide `pilos-secrets` holding them,
pulled in via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)).
The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `pilos-db` and a Redis.

## Persistence

Uploaded logos and files live on a ReadWriteOnce volume, so this is **one replica,
recreated**. The bundled nginx master needs root and a writable root filesystem.

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
metadata: { name: kurly, namespace: pilos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pilos, namespace: pilos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pilos, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pilos }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pilos, namespace: pilos }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pilos } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pilos, namespace: pilos }
spec:
  serviceAccountName: pilos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pilos/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pilos, importPath: github.com/metio/kurly/workloads/pilos }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pilos, namespace: pilos }
spec:
  serviceAccountName: pilos-deployer
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
        name: pilos
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pilos }
```

<!-- END generated: jaas-deploy -->
