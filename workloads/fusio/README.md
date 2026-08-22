<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fusio

[Fusio](https://www.fusio-project.org/) — an open-source API management platform
for building, securing and documenting HTTP APIs. A plain composable `kurly.http`
workload on the official Apache/PHP image, backed by an external MySQL/MariaDB or
PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fusio = import 'github.com/metio/kurly/workloads/fusio/server.libsonnet';

kurly.list(fusio(appUrl='https://api.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `fusio` | |
| `image` | `docker.io/fusio/fusio:7.1.1` | |
| `replicas` | `1` | stateless, so it scales horizontally |
| `appUrl` / `appsUrl` | unset | the public URL, and where the apps are served |
| `backendUser` / `backendEmail` | `admin` / `admin@example.com` | the initial backend user |
| `secretName` | `fusio` | Secret with `FUSIO_CONNECTION`, `FUSIO_PROJECT_KEY` and `FUSIO_BACKEND_PW` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the API and the backend on `:80` — compose an exposure onto it.

## Database and secrets

Fusio needs a **MySQL/MariaDB or PostgreSQL** database — the
[mysql-cluster](../mysql-cluster/) and [cnpg-cluster](../cnpg-cluster/) workloads
provide one. It takes the whole connection as a Doctrine DSN in
`FUSIO_CONNECTION` (`pdo-mysql://user:pass@host/db` or `pdo-pgsql://…`), alongside
`FUSIO_PROJECT_KEY` — the key its tokens are signed with, which must stay stable
for the life of an installation — and `FUSIO_BACKEND_PW`, the password of the
backend user created on first start. All three come from a provided Secret via
`envFrom`; kurly authors **no Secret**.

## Security and startup

The entrypoint waits for the database, migrates the schema, creates the initial
backend user and then starts cron, supervisor and Apache as **root**, so this
workload relaxes kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities (only the ones Apache needs to bind `:80` and drop to
`www-data` are granted back) and no privilege escalation. That first run takes
minutes before anything listens, so it has a **startup probe** rather than a long
liveness delay.

Everything Fusio keeps lives in the database, so this workload claims no volume.

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
metadata: { name: kurly, namespace: fusio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-fusio, namespace: fusio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/fusio, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: fusio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-fusio, namespace: fusio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-fusio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: fusio, namespace: fusio }
spec:
  serviceAccountName: fusio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/fusio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-fusio, importPath: github.com/metio/kurly/workloads/fusio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: fusio, namespace: fusio }
spec:
  serviceAccountName: fusio-deployer
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
        name: fusio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: fusio }
```

<!-- END generated: jaas-deploy -->
