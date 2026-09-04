<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fossbilling

[FOSSBilling](https://fossbilling.org/) — hosting and billing automation with a
client area, an admin panel and a full API. A plain composable `kurly.http` workload
on the [official image](https://hub.docker.com/r/fossbilling/fossbilling) (Apache,
PHP and the five-minute cron run in one container), backed by an external
MySQL/MariaDB, with its whole install tree on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fossbilling = import 'github.com/metio/kurly/workloads/fossbilling/server.libsonnet';

kurly.list(fossbilling())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `fossbilling` | |
| `image` | `docker.io/fossbilling/fossbilling:0.8.7` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the install tree (`/var/www/html`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and installation

FOSSBilling needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. Its coordinates are entered in the web installer on first
visit, which writes them into `config.php` inside the install tree, so kurly authors
**no Secret** and this stage reads none. Visit the deployment once after rolling it
out and finish the installer before pointing anyone else at it.

## Storage and first boot

The application, its configuration and its uploads all live in one tree, and
upstream persists exactly that path. A PersistentVolume arrives empty and would hide
the application the image ships — a Docker named volume is seeded from the image, and
Kubernetes does no such thing — so an init container mounts the same volume
elsewhere and copies the image's tree in when it finds no `index.php`. With one
present the copy is skipped, so an installed instance's `config.php` and uploads are
never overwritten.

## Security and persistence

Apache starts as **root** to bind `:80` and drops its workers to `www-data`, so this
workload relaxes kurly's non-root default and grants back only the capabilities that
change identity and reach the files `www-data` owns. Apache, cron and PHP each write
outside the volume (pid files, sockets, sessions), so the root filesystem is
writable. The install tree lives on a ReadWriteOnce volume, so this is **one replica,
recreated**.

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
metadata: { name: kurly, namespace: fossbilling }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-fossbilling, namespace: fossbilling }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/fossbilling, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: fossbilling }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-fossbilling, namespace: fossbilling }
spec: { sourceRef: { kind: OCIRepository, name: kurly-fossbilling } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: fossbilling, namespace: fossbilling }
spec:
  serviceAccountName: fossbilling-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/fossbilling/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-fossbilling, importPath: github.com/metio/kurly/workloads/fossbilling }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: fossbilling, namespace: fossbilling }
spec:
  serviceAccountName: fossbilling-deployer
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
        name: fossbilling
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: fossbilling }
```

<!-- END generated: jaas-deploy -->
