<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mediawiki

[MediaWiki](https://www.mediawiki.org/) — the wiki engine behind Wikipedia. A plain
composable `kurly.http` workload on the official image, backed by an external
MySQL/MariaDB, with its uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mediawiki = import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet';

kurly.list(mediawiki())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mediawiki` | |
| `image` | `docker.io/library/mediawiki:1.45.4` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | uploaded files (`/var/www/html/images`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the wiki on `:80` — compose an exposure onto it.

## Configuration

MediaWiki is configured by a `LocalSettings.php` (database credentials, secret keys,
extensions). Generate it once with the web installer, or author it, and mount it at
`/var/www/html/LocalSettings.php` from a Secret (it holds the database password and
`$wgSecretKey`) — kurly authors **none**. The database is a **MySQL/MariaDB** — the
[mysql-cluster](../mysql-cluster/) workload provides one.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. Uploaded files live on a ReadWriteOnce volume, so this is
**one replica, recreated**.

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
metadata: { name: kurly, namespace: mediawiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mediawiki, namespace: mediawiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mediawiki, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mediawiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mediawiki, namespace: mediawiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mediawiki } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mediawiki, namespace: mediawiki }
spec:
  serviceAccountName: mediawiki-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mediawiki, importPath: github.com/metio/kurly/workloads/mediawiki }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mediawiki, namespace: mediawiki }
spec:
  serviceAccountName: mediawiki-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mediawiki
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mediawiki }
```

<!-- END generated: jaas-deploy -->
