<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vvveb-cms

[Vvveb CMS](https://www.vvveb.com/) — a content management system whose pages are
edited by dragging blocks around rather than by writing markup. A composable
`kurly.http` workload on the project's own nginx + php-fpm image, with the whole
application tree on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vvveb = import 'github.com/metio/kurly/workloads/vvveb-cms/server.libsonnet';

kurly.list(vvveb())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vvveb-cms` | |
| `image` | `docker.io/vvveb/vvvebcms:latest` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the application tree (`/var/www/html`) |
| `downloadUrl` | the image's own default | where the first boot fetches the release from |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## The first boot downloads the application

The image ships PHP, nginx and an entry point; the CMS itself is fetched as a zip
from `DOWNLOAD_URL` and unpacked into `/var/www/html` the first time that directory
is empty. So the first start needs **egress to the download host** and takes minutes
rather than seconds — the startup probe allows ten of them — and the volume is
mounted at the application root rather than at a data directory, because code,
configuration, themes, uploads and the page cache all live there together. Later
boots find the tree and skip the download. Set `downloadUrl` to deploy from a mirror
instead, on a cluster with no egress to `vvveb.com`.

## Database

Vvveb needs a **MySQL/MariaDB or PostgreSQL** — the [mysql-cluster](../mysql-cluster/)
and [cnpg-cluster](../cnpg-cluster/) workloads provide one. Which engine, and the
credentials for it, are entered in the **web installer** on first visit and written
to the configuration on the volume; they are not read from the environment. kurly
therefore passes no database coordinates and authors **no Secret**.

## Security and persistence

supervisord runs nginx and php-fpm together and drops both to `www-data`, which it
can only do from **root**; nginx binds `:80` and the entry point chowns the unpacked
tree. So this workload relaxes kurly's non-root default and keeps the image's
capabilities, and the read-only root filesystem is relaxed because nginx, php-fpm and
supervisord keep their pid files, logs and temporary request bodies inside the
image's own tree. The application tree is a ReadWriteOnce volume, so this is **one
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
metadata: { name: kurly, namespace: vvveb-cms }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vvveb-cms, namespace: vvveb-cms }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vvveb-cms, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vvveb-cms }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vvveb-cms, namespace: vvveb-cms }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vvveb-cms } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vvveb-cms, namespace: vvveb-cms }
spec:
  serviceAccountName: vvveb-cms-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vvveb-cms/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vvveb-cms, importPath: github.com/metio/kurly/workloads/vvveb-cms }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vvveb-cms, namespace: vvveb-cms }
spec:
  serviceAccountName: vvveb-cms-deployer
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
        name: vvveb-cms
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vvveb-cms }
```

<!-- END generated: jaas-deploy -->
