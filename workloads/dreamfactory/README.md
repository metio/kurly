<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dreamfactory

[DreamFactory](https://www.dreamfactory.com) — generates a documented REST API
over databases and services you already have, with roles, API keys and rate
limits in front of it. A composable `kurly.http` workload: its own configuration
and user accounts live in an external database, and the APIs it generates reach
whatever it is pointed at.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dreamfactory = import 'github.com/metio/kurly/workloads/dreamfactory/server.libsonnet';

kurly.list(dreamfactory(
  dbHost='dreamfactory-db',
  secretName='dreamfactory',
  serverName='api.example.com',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dreamfactory` | |
| `image` | the pinned upstream image | |
| `dbDriver` | `mysql` | or `pgsql`, `sqlsrv` |
| `dbHost` / `dbPort` / `database` / `dbUser` | none / none / `dreamfactory` / `dreamfactory` | DreamFactory's own database |
| `secretName` | none | `APP_KEY` and `DB_PASSWORD` |
| `serverName` | none | the hostname nginx answers for |
| `behindTlsProxy` | `true` | makes Laravel build https links |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the admin console and the generated APIs on `:80` — compose an exposure
onto it.

## The entrypoint rewrites the application tree

On every start it edits `.env` in place with `sed`, links an nginx site, rewrites
php-fpm's pool configuration and may run `composer install` — all inside the
image, as root, before nginx and php-fpm start and drop to `www-data`. That needs
a root container, a writable root filesystem and the runtime's default
capabilities. Each is relaxed here rather than pretended away, and the catalogue
reports the resulting posture.

## The app key belongs in the Secret

The image generates one on first start and keeps it in `.env` — which is inside
the container, so it is regenerated on every restart, and every session and
encrypted field from the previous one becomes unreadable:

```shell
kubectl create secret generic dreamfactory \
  --from-literal=APP_KEY="base64:$(head -c32 /dev/urandom | base64)" \
  --from-literal=DB_PASSWORD='…'
```

## What it can reach is the point and the risk

DreamFactory's job is to open an API onto other systems, so an operator with admin
access can point it at any address this pod can reach. A NetworkPolicy limiting
egress to the databases it is meant to expose is worth composing on.

One replica, recreated: the shipped configuration keeps sessions and cache on
local disk, so a second pod would answer with a different view of both.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: dreamfactory }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dreamfactory, namespace: dreamfactory }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dreamfactory, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dreamfactory }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dreamfactory, namespace: dreamfactory }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dreamfactory } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dreamfactory, namespace: dreamfactory }
spec:
  serviceAccountName: dreamfactory-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/dreamfactory/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dreamfactory, importPath: github.com/metio/kurly/workloads/dreamfactory }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dreamfactory, namespace: dreamfactory }
spec:
  serviceAccountName: dreamfactory-deployer
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
        name: dreamfactory
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: dreamfactory }
```

<!-- END generated: jaas-deploy -->
