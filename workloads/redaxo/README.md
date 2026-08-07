<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redaxo

[REDAXO](https://www.redaxo.org/) — a content management system built around a
structured editor: an article is composed from typed modules rather than typed
into one rich-text field, so the shape of the content survives the person who
entered it. A plain composable `kurly.http` workload on the project's own image,
backed by an external MySQL/MariaDB, with the whole application tree on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local redaxo = import 'github.com/metio/kurly/workloads/redaxo/server.libsonnet';

kurly.list(redaxo(server='https://cms.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `redaxo` | |
| `image` | `docker.io/friendsofredaxo/redaxo:5` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/var/www/html` — the whole tree |
| `dbHost` / `database` / `dbUser` | `redaxo-db` / `redaxo` / `redaxo` | |
| `dbCharset` | `utf8mb4` | |
| `server` / `serverName` | unset | the public URL and the site name beside it |
| `errorEmail` | unset | where error reports are mailed |
| `lang` / `timezone` | `en_gb` / `UTC` | backend language and timezone |
| `adminUser` | `admin` | the account setup creates |
| `secretName` | `redaxo` | Secret with `REDAXO_DB_PASSWORD` and `REDAXO_ADMIN_PASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:80` — compose an exposure onto it.

## Database and secrets

REDAXO needs a **MySQL/MariaDB** database — the
[mysql-cluster](../mysql-cluster/) workload provides one — and the database must
already **exist**, because setup runs with `--db-createdb=no`. The entrypoint
writes the connection into the copied tree and then runs the installer, so a
reachable server is a prerequisite of the **first boot**, not only of serving; it
retries for about a minute and then gives up and fails the pod.

Coordinates travel as environment, while `REDAXO_DB_PASSWORD` and
`REDAXO_ADMIN_PASSWORD` come from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `redaxo` with
[`kurly.externalSecret`](../../main.libsonnet).

Set `server` to the URL the installation is reached at, or REDAXO keeps the
installer's own default and the links it builds point somewhere that is not this
installation.

Every optional `REDAXO_*` variable is rendered even when empty. The entrypoint
runs under `set -u` and reads them all unconditionally, so an *unset* optional
variable aborts setup with an unbound-variable error before Apache ever starts,
which reads as a broken image rather than a missing parameter.

## Security and persistence

Setup copies `/usr/src/redaxo` into the document root, runs the installer and
chowns the writable directories to `www-data` before Apache forks its workers as
`www-data`. All of that needs **root**, its capabilities and a **writable image
tree**, so this workload relaxes those defaults deliberately.

The entrypoint installs only into an **empty** document root — on every later
start it finds the tree and skips setup, which is what makes the volume the
installation rather than a cache. The tree, the installed addons and the uploaded
media therefore live together on a ReadWriteOnce volume: **one replica,
recreated**.

Probes are by **connection**, not by path: the document root redirects into the
backend login, and following that redirect would fail a probe on an installation
that is working perfectly.

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
metadata: { name: kurly, namespace: redaxo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-redaxo, namespace: redaxo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/redaxo, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: redaxo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-redaxo, namespace: redaxo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-redaxo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: redaxo, namespace: redaxo }
spec:
  serviceAccountName: redaxo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/redaxo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-redaxo, importPath: github.com/metio/kurly/workloads/redaxo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: redaxo, namespace: redaxo }
spec:
  serviceAccountName: redaxo-deployer
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
        name: redaxo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: redaxo }
```

<!-- END generated: jaas-deploy -->
