<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# part-db

[Part-DB](https://github.com/Part-DB/Part-DB-server) — an inventory for electronic
components: what parts you have, how many are left, where they sit, and the
datasheets that belong to them. A composable `kurly.http` workload on the official
image, keeping its database, attachments and public media on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local partdb = import 'github.com/metio/kurly/workloads/part-db/server.libsonnet';

kurly.list(partdb())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `part-db` | |
| `image` | `docker.io/jbtronics/part-db1:v2.15.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/www/html/uploads` |
| `mediaStorageSize` | `2Gi` | `/var/www/html/public/media` |
| `databaseUrl` | unset | a Doctrine DSN; unset keeps SQLite |
| `instanceName` / `defaultLanguage` / `defaultTimezone` / `baseCurrency` | `Part-DB` / `en` / `UTC` / `EUR` | |

The first account is created interactively on first visit — nothing here mints a
credential, so no Secret is needed to start.

## Database

The image stores everything in a SQLite file inside the uploads volume, which is
why this workload needs nothing external. For more than a single user, point it at
a real server — the image carries both the MySQL and the PostgreSQL PDO driver:

```jsonnet
partdb(databaseUrl='postgresql://part-db:…@part-db-db-rw:5432/part-db?serverVersion=17')
```

The DSN carries the password, so pass it through a Secret (compose
`kurly.envFromSecret('part-db')` with a `DATABASE_URL` key) rather than writing it
into the rendered manifest. Switching backends does not migrate the SQLite file;
export first, or start on the server you mean to keep.

## Less hardened, deliberately

Apache and php-fpm start as root, bind `:80`, and the entrypoint chowns the volumes
before dropping to `www-data` — so this runs as root with privilege escalation and
the default capabilities. The root filesystem is writable because Symfony warms its
cache into `/var/www/html/var` inside the image's own tree.

## Persistence

The database, attachments and media live on ReadWriteOnce volumes, so this is **one
replica, recreated** (never rolled). The first boot runs the Doctrine migrations and
builds the cache before Apache answers, which is what the generous startup probe
budget is for.

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
metadata: { name: kurly, namespace: part-db }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-part-db, namespace: part-db }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/part-db, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: part-db }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-part-db, namespace: part-db }
spec: { sourceRef: { kind: OCIRepository, name: kurly-part-db } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: part-db, namespace: part-db }
spec:
  serviceAccountName: part-db-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/part-db/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-part-db, importPath: github.com/metio/kurly/workloads/part-db }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: part-db, namespace: part-db }
spec:
  serviceAccountName: part-db-deployer
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
        name: part-db
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: part-db }
```

<!-- END generated: jaas-deploy -->
