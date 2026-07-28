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
| `image` | `docker.io/library/wordpress:6.9.4-php8.3-apache` | |
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

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: wordpress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wordpress, namespace: wordpress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wordpress, ref: { tag: latest } }
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
