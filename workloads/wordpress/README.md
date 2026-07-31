<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wordpress

[WordPress](https://wordpress.org/) — the world's most popular CMS and blogging
platform. A plain composable `kurly.http` workload on the official image, backed by
an external MySQL/MariaDB, with its content (themes, plugins, uploads) on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wordpress = import 'github.com/metio/kurly/workloads/wordpress/server.libsonnet';

kurly.list(wordpress())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wordpress` | |
| `image` | `docker.io/library/wordpress:7.0.2-php8.3-apache` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | content (`/var/www/html`) |
| `dbHost` / `dbName` / `dbUser` | `wordpress-db` / `wordpress` / `wordpress` | the MySQL/MariaDB database |
| `secretName` | `wordpress-secrets` | Secret with `WORDPRESS_DB_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the site on `:80` — compose an exposure onto it.

## Database and secrets

WordPress needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe — bring your
own and point `dbHost` at it. It reads `WORDPRESS_DB_HOST`, `WORDPRESS_DB_NAME`,
`WORDPRESS_DB_USER` from env and `WORDPRESS_DB_PASSWORD` from a provided Secret via
`envFrom`. kurly authors **no Secret** — fill `wordpress-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. The content lives on a ReadWriteOnce volume, so this is **one
replica, recreated**.

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
metadata: { name: kurly, namespace: wordpress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wordpress, namespace: wordpress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wordpress, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wordpress }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wordpress, namespace: wordpress }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wordpress } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wordpress, namespace: wordpress }
spec:
  serviceAccountName: wordpress-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wordpress/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wordpress, importPath: github.com/metio/kurly/workloads/wordpress }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wordpress, namespace: wordpress }
spec:
  serviceAccountName: wordpress-deployer
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
        name: wordpress
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wordpress }
```

<!-- END generated: jaas-deploy -->
