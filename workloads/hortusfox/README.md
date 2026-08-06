<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hortusfox

[HortusFox](https://github.com/danielbrendel/hortusfox-web) — collaborative plant
management: what grows where, when it was last watered, and the photo log that shows
how it is doing. A plain composable `kurly.http` workload on the official image,
backed by an external MySQL/MariaDB, with plant photos and attachments on
PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hortusfox = import 'github.com/metio/kurly/workloads/hortusfox/server.libsonnet';

kurly.list(hortusfox())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `hortusfox` | |
| `image` | `ghcr.io/danielbrendel/hortusfox-web:v5.9` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | plant photos (`/var/www/html/public/img`) |
| `attachmentsStorageSize` | `5Gi` | attachments (`/var/www/html/public/attachments`) |
| `dbHost` / `dbPort` / `database` / `dbUser` / `dbCharset` | `hortusfox-db` / `3306` / `hortusfox` / `hortusfox` / `utf8mb4` | the MySQL/MariaDB database |
| `adminEmail` / `timezone` | `admin@example.com` / `UTC` | the administrator seeded on first boot |
| `secretName` | `hortusfox` | Secret with `DB_PASSWORD` and `APP_ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

HortusFox needs a **MySQL/MariaDB** database — the [mysql-cluster](../mysql-cluster/)
workload provides one. Its coordinates come from env; `DB_PASSWORD` and
`APP_ADMIN_PASSWORD` come from a Secret via `envFrom`. `APP_ADMIN_PASSWORD` is the
password of the administrator account the first boot seeds, so it is a credential
somebody logs in with, not a throwaway. kurly authors **no Secret**.

## Security and persistence

The Apache + PHP image starts as **root**, binds `:80`, and its entrypoint takes
ownership of the mounted directories before dropping to `www-data`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults. The application also keeps
its logs, backups, themes and migration state beside its own code inside the image
tree, which the writable root filesystem covers — only the photos and attachments
are worth a volume. Both are ReadWriteOnce, so this is **one replica, recreated**.

The first boot migrates the schema and seeds the administrator before Apache answers,
which is what the generous startup probe is for; the liveness clock only starts once
it has passed.

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
metadata: { name: kurly, namespace: hortusfox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hortusfox, namespace: hortusfox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hortusfox, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hortusfox }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hortusfox, namespace: hortusfox }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hortusfox } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hortusfox, namespace: hortusfox }
spec:
  serviceAccountName: hortusfox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hortusfox/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hortusfox, importPath: github.com/metio/kurly/workloads/hortusfox }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hortusfox, namespace: hortusfox }
spec:
  serviceAccountName: hortusfox-deployer
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
        name: hortusfox
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hortusfox }
```

<!-- END generated: jaas-deploy -->
